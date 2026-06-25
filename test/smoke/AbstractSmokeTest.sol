// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Foundry imports
import {Test} from "forge-std/Test.sol";

import {DeployManager} from "script/deploy/DeployManager.s.sol";
import {$031_UpgradeEthenaARMScript} from "script/deploy/mainnet/031_UpgradeEthenaARMScript.s.sol";
import {$032_UpgradeEtherFiARMSwapFeeScript} from "script/deploy/mainnet/032_UpgradeEtherFiARMSwapFeeScript.s.sol";
import {$033_UpgradeLidoARMSwapFeeScript} from "script/deploy/mainnet/033_UpgradeLidoARMSwapFeeScript.s.sol";
import {Resolver} from "script/deploy/helpers/Resolver.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {OriginAssetAdapter} from "contracts/adapters/OriginAssetAdapter.sol";
import {WrappedOriginAssetAdapter} from "contracts/adapters/WrappedOriginAssetAdapter.sol";

abstract contract AbstractSmokeTest is Test {
    /// @dev First derived-contract storage slot after AbstractARM's reserved gap.
    uint256 internal constant LEGACY_PENDING_AMOUNT_SLOT = 100;
    uint256 internal constant FEE_SCALE = 10000;
    uint256 internal constant DELAY_REQUEST = 30 minutes;
    /// @dev Ethena ARM proxy from mainnet deployment history. `Mainnet` does not expose this address.
    address internal constant ETHENA_ARM_PROXY = 0xCEDa2d856238aA0D12f6329de20B9115f07C366d;

    Resolver internal resolver = Resolver(address(uint160(uint256(keccak256("Resolver")))));

    DeployManager internal deployManager;

    /// @notice Using setUp here instead of a constructor because in case of failing test,
    ///         constructors logs are not printed, while setUp logs are printed.
    function setUp() public virtual {
        // Check if the MAINNET_URL is set.
        require(vm.envExists("MAINNET_URL"), "MAINNET_URL not set");

        // Create a fork.
        // If block number is provided in the environment variables, use it.
        // Otherwise, use latest block.
        if (vm.envExists("FORK_BLOCK_NUMBER_MAINNET")) {
            uint256 blockNumber = vm.envUint("FORK_BLOCK_NUMBER_MAINNET");
            vm.createSelectFork(vm.envString("MAINNET_URL"), blockNumber);
        } else {
            vm.createSelectFork(vm.envString("MAINNET_URL"));
        }

        deployManager = new DeployManager();

        // Run deployments
        deployManager.setUp();
        _clearLegacyPendingAmount(ETHENA_ARM_PROXY);
        deployManager.run();
        _runPendingEthena031ForSmoke();
        _applyPendingMultiBaseUpgrades();
    }

    function _applyPendingMultiBaseUpgrades() internal {
        _upgradeLidoARM();
        _upgradeEtherFiARM();
        _upgradeEthenaARM();
        _upgradeOriginARM();
    }

    function _runPendingEthena031ForSmoke() internal {
        (bool hasBaseAssetConfigs,) =
            ETHENA_ARM_PROXY.staticcall(abi.encodeWithSignature("baseAssetConfigs(address)", Mainnet.SUSDE));
        if (hasBaseAssetConfigs) return;

        _clearLegacyPendingAmount(ETHENA_ARM_PROXY);
        new $031_UpgradeEthenaARMScript().run();
    }

    function _upgradeLidoARM() internal {
        Proxy proxy = Proxy(payable(resolver.resolve("LIDO_ARM")));

        _clearLegacyPendingAmount(address(proxy));
        _clearLegacyWithdrawQueueForSmoke(address(proxy));
        // 033 deploys the stETH/wstETH adapters and registers them (stETH tradable, wstETH dormant) under
        // LIDO_ARM_STETH_ADAPTER / LIDO_ARM_WSTETH_ADAPTER, so the smoke test no longer deploys or
        // registers them itself.
        new $033_UpgradeLidoARMSwapFeeScript().run();
    }

    function _upgradeEtherFiARM() internal {
        Proxy proxy = Proxy(payable(resolver.resolve("ETHER_FI_ARM")));

        _clearLegacyPendingAmount(address(proxy));
        _clearLegacyWithdrawQueueForSmoke(address(proxy));
        // 032 deploys the eETH/weETH adapters and registers them (eETH tradable, weETH dormant) under
        // ETHER_FI_ARM_EETH_ADAPTER / ETHER_FI_ARM_WEETH_ADAPTER, so the smoke test no longer deploys
        // or registers them itself.
        new $032_UpgradeEtherFiARMSwapFeeScript().run();
    }

    function _upgradeEthenaARM() internal {
        // 031 (run by _runPendingEthena031ForSmoke) deploys the sUSDe adapter, upgrades the ARM,
        // registers sUSDe (active) and deploys the unstakers, so the smoke test no longer does it here.
    }

    function _upgradeOriginARM() internal {
        Proxy proxy = Proxy(payable(resolver.resolve("OETH_ARM")));
        OriginARM impl = new OriginARM(Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT, 10 minutes, 1e7, 1e18);
        resolver.addContract("OETH_ARM_IMPL", address(impl));

        _clearLegacyPendingAmount(address(proxy));

        vm.prank(proxy.owner());
        proxy.upgradeTo(address(impl));

        _clearLegacyWithdrawQueueForSmoke(address(proxy));

        OriginAssetAdapter oethAdapterImpl =
            new OriginAssetAdapter(address(proxy), Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT);
        resolver.addContract("OETH_ARM_OETH_ADAPTER_IMPL", address(oethAdapterImpl));
        Proxy oethAdapterProxy = new Proxy();
        oethAdapterProxy.initialize(address(oethAdapterImpl), Mainnet.TIMELOCK, abi.encodeWithSignature("initialize()"));
        resolver.addContract("OETH_ARM_OETH_ADAPTER", address(oethAdapterProxy));

        WrappedOriginAssetAdapter woethAdapterImpl = new WrappedOriginAssetAdapter(
            address(proxy), Mainnet.WOETH, Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT
        );
        resolver.addContract("OETH_ARM_WOETH_ADAPTER_IMPL", address(woethAdapterImpl));
        Proxy woethAdapterProxy = new Proxy();
        woethAdapterProxy.initialize(
            address(woethAdapterImpl), Mainnet.TIMELOCK, abi.encodeWithSignature("initialize()")
        );
        resolver.addContract("OETH_ARM_WOETH_ADAPTER", address(woethAdapterProxy));

        OriginARM arm = OriginARM(payable(address(proxy)));
        vm.startPrank(arm.owner());
        _addBaseAssetIfMissing(arm, Mainnet.OETH, address(oethAdapterProxy), 0.9994e36, 1e36, 0.99996e36, true);
        _addBaseAssetIfMissing(arm, Mainnet.WOETH, address(woethAdapterProxy), 0.9994e36, 1e36, 0.99996e36, false);
        vm.stopPrank();
    }

    function _clearLegacyPendingAmount(address arm) internal {
        // Smoke tests exercise the post-upgrade ARM shape. Production upgrades still require
        // operators to drain legacy protocol queues before adapter-owned withdrawals are enabled.
        vm.store(arm, bytes32(LEGACY_PENDING_AMOUNT_SLOT), bytes32(0));
    }

    function _clearLegacyWithdrawQueueForSmoke(address arm) internal pure {
        (arm);
        // Legacy LP withdrawals are now preserved for post-upgrade claims.
    }

    function _addBaseAssetIfMissing(
        LidoARM arm,
        address baseAsset,
        address adapter,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 crossPrice,
        bool peggedToLiquidityAsset
    ) internal {
        (,,,,,,,, address configuredAdapter) = arm.baseAssetConfigs(baseAsset);
        if (configuredAdapter == address(0)) {
            arm.addBaseAsset(
                baseAsset,
                adapter,
                buyPrice,
                sellPrice,
                type(uint128).max,
                type(uint128).max,
                crossPrice,
                peggedToLiquidityAsset
            );
        }
    }

    function _addBaseAssetIfMissing(
        EtherFiARM arm,
        address baseAsset,
        address adapter,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 crossPrice,
        bool peggedToLiquidityAsset
    ) internal {
        (,,,,,,,, address configuredAdapter) = arm.baseAssetConfigs(baseAsset);
        if (configuredAdapter == address(0)) {
            arm.addBaseAsset(
                baseAsset,
                adapter,
                buyPrice,
                sellPrice,
                type(uint128).max,
                type(uint128).max,
                crossPrice,
                peggedToLiquidityAsset
            );
        }
    }

    function _addBaseAssetIfMissing(
        EthenaARM arm,
        address baseAsset,
        address adapter,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 crossPrice,
        bool peggedToLiquidityAsset
    ) internal {
        (,,,,,,,, address configuredAdapter) = arm.baseAssetConfigs(baseAsset);
        if (configuredAdapter == address(0)) {
            arm.addBaseAsset(
                baseAsset,
                adapter,
                buyPrice,
                sellPrice,
                type(uint128).max,
                type(uint128).max,
                crossPrice,
                peggedToLiquidityAsset
            );
        }
    }

    function _addBaseAssetIfMissing(
        OriginARM arm,
        address baseAsset,
        address adapter,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 crossPrice,
        bool peggedToLiquidityAsset
    ) internal {
        (,,,,,,,, address configuredAdapter) = arm.baseAssetConfigs(baseAsset);
        if (configuredAdapter == address(0)) {
            arm.addBaseAsset(
                baseAsset,
                adapter,
                buyPrice,
                sellPrice,
                type(uint128).max,
                type(uint128).max,
                crossPrice,
                peggedToLiquidityAsset
            );
        }
    }

    /// @dev Assert `expected` appears in the ARM's `getBaseAssets()` list. A membership check
    ///      rather than exact array equality keeps the assertion robust to registration order and
    ///      to additional base assets being registered by future deployments.
    function _assertBaseAssetListed(address[] memory baseAssets, address expected, string memory label) internal pure {
        bool found = false;
        for (uint256 i = 0; i < baseAssets.length; ++i) {
            if (baseAssets[i] == expected) {
                found = true;
                break;
            }
        }
        assertTrue(found, label);
    }
}
