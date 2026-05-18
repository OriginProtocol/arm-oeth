// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Foundry imports
import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";

import {DeployManager} from "script/deploy/DeployManager.s.sol";
import {$028_UpgradeEthenaARMScript} from "script/deploy/mainnet/028_UpgradeEthenaARMScript.s.sol";
import {Resolver} from "script/deploy/helpers/Resolver.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {StETHAssetAdapter} from "contracts/adapters/StETHAssetAdapter.sol";
import {WstETHAssetAdapter} from "contracts/adapters/WstETHAssetAdapter.sol";
import {EtherFiAssetAdapter} from "contracts/adapters/EtherFiAssetAdapter.sol";
import {WeETHAssetAdapter} from "contracts/adapters/WeETHAssetAdapter.sol";
import {EthenaAssetAdapter} from "contracts/adapters/EthenaAssetAdapter.sol";
import {OriginAssetAdapter} from "contracts/adapters/OriginAssetAdapter.sol";
import {WrappedOriginAssetAdapter} from "contracts/adapters/WrappedOriginAssetAdapter.sol";

abstract contract AbstractSmokeTest is Test {
    using stdStorage for StdStorage;

    /// @dev First derived-contract storage slot after AbstractARM's reserved gap.
    uint256 internal constant LEGACY_PENDING_AMOUNT_SLOT = 100;
    uint256 internal constant FEE_SCALE = 10000;
    uint256 internal constant DELAY_REQUEST = 30 minutes;
    bytes4 internal constant INVALID_INITIALIZATION = 0xf92ee8a9;
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
        _runPendingEthena028ForSmoke();
        _applyPendingMultiBaseUpgrades();
    }

    function _applyPendingMultiBaseUpgrades() internal {
        _upgradeLidoARM();
        _upgradeEtherFiARM();
        _upgradeEthenaARM();
        _upgradeOriginARM();
    }

    function _runPendingEthena028ForSmoke() internal {
        (bool hasBaseAssetConfigs,) =
            ETHENA_ARM_PROXY.staticcall(abi.encodeWithSignature("baseAssetConfigs(address)", Mainnet.SUSDE));
        if (hasBaseAssetConfigs) return;

        _clearLegacyPendingAmount(ETHENA_ARM_PROXY);
        new $028_UpgradeEthenaARMScript().run();
    }

    function _upgradeLidoARM() internal {
        Proxy proxy = Proxy(payable(resolver.resolve("LIDO_ARM")));
        LidoARM impl = new LidoARM(Mainnet.WETH, 10 minutes, 1e7, 1e18);
        resolver.addContract("LIDO_ARM_IMPL", address(impl));

        _clearLegacyPendingAmount(address(proxy));

        vm.prank(proxy.owner());
        proxy.upgradeTo(address(impl));

        _clearLegacyWithdrawQueueForSmoke(address(proxy));
        _migrateLegacyWithdrawQueue(address(proxy));

        StETHAssetAdapter stethAdapterImpl =
            new StETHAssetAdapter(address(proxy), Mainnet.WETH, Mainnet.STETH, Mainnet.LIDO_WITHDRAWAL);
        resolver.addContract("LIDO_ARM_STETH_ADAPTER_IMPL", address(stethAdapterImpl));
        Proxy stethAdapterProxy = new Proxy();
        stethAdapterProxy.initialize(
            address(stethAdapterImpl), Mainnet.TIMELOCK, abi.encodeWithSignature("initialize()")
        );
        resolver.addContract("LIDO_ARM_STETH_ADAPTER", address(stethAdapterProxy));

        WstETHAssetAdapter wstethAdapterImpl = new WstETHAssetAdapter(
            address(proxy), Mainnet.WETH, Mainnet.STETH, Mainnet.WSTETH, Mainnet.LIDO_WITHDRAWAL
        );
        resolver.addContract("LIDO_ARM_WSTETH_ADAPTER_IMPL", address(wstethAdapterImpl));
        Proxy wstethAdapterProxy = new Proxy();
        wstethAdapterProxy.initialize(
            address(wstethAdapterImpl), Mainnet.TIMELOCK, abi.encodeWithSignature("initialize()")
        );
        resolver.addContract("LIDO_ARM_WSTETH_ADAPTER", address(wstethAdapterProxy));

        LidoARM arm = LidoARM(payable(address(proxy)));
        vm.startPrank(arm.owner());
        _addBaseAssetIfMissing(arm, Mainnet.STETH, address(stethAdapterProxy), 0.9996e36, 1e36, 0.99996e36, true);
        _addBaseAssetIfMissing(arm, Mainnet.WSTETH, address(wstethAdapterProxy), 0.9996e36, 1e36, 0.99996e36, false);
        vm.stopPrank();
    }

    function _upgradeEtherFiARM() internal {
        Proxy proxy = Proxy(payable(resolver.resolve("ETHER_FI_ARM")));
        EtherFiARM impl = new EtherFiARM(Mainnet.EETH, Mainnet.WETH, 10 minutes, 1e7, 1e18);
        resolver.addContract("ETHER_FI_ARM_IMPL", address(impl));

        _clearLegacyPendingAmount(address(proxy));

        vm.prank(proxy.owner());
        proxy.upgradeTo(address(impl));

        _clearLegacyWithdrawQueueForSmoke(address(proxy));
        _migrateLegacyWithdrawQueue(address(proxy));

        EtherFiAssetAdapter eethAdapterImpl = new EtherFiAssetAdapter(
            address(proxy), Mainnet.EETH, Mainnet.WETH, Mainnet.ETHERFI_WITHDRAWAL, Mainnet.ETHERFI_WITHDRAWAL_NFT
        );
        resolver.addContract("ETHER_FI_ARM_EETH_ADAPTER_IMPL", address(eethAdapterImpl));
        Proxy eethAdapterProxy = new Proxy();
        eethAdapterProxy.initialize(address(eethAdapterImpl), Mainnet.TIMELOCK, abi.encodeWithSignature("initialize()"));
        resolver.addContract("ETHER_FI_ARM_EETH_ADAPTER", address(eethAdapterProxy));

        WeETHAssetAdapter weethAdapterImpl = new WeETHAssetAdapter(
            address(proxy),
            Mainnet.WEETH,
            Mainnet.EETH,
            Mainnet.WETH,
            Mainnet.ETHERFI_WITHDRAWAL,
            Mainnet.ETHERFI_WITHDRAWAL_NFT
        );
        resolver.addContract("ETHER_FI_ARM_WEETH_ADAPTER_IMPL", address(weethAdapterImpl));
        Proxy weethAdapterProxy = new Proxy();
        weethAdapterProxy.initialize(
            address(weethAdapterImpl), Mainnet.TIMELOCK, abi.encodeWithSignature("initialize()")
        );
        resolver.addContract("ETHER_FI_ARM_WEETH_ADAPTER", address(weethAdapterProxy));

        EtherFiARM arm = EtherFiARM(payable(address(proxy)));
        vm.startPrank(arm.owner());
        _addBaseAssetIfMissing(arm, Mainnet.EETH, address(eethAdapterProxy), 0.9996e36, 1e36, 0.99996e36, true);
        _addBaseAssetIfMissing(arm, Mainnet.WEETH, address(weethAdapterProxy), 0.9996e36, 1e36, 0.99996e36, false);
        vm.stopPrank();
    }

    function _upgradeEthenaARM() internal {
        Proxy proxy = Proxy(payable(resolver.resolve("ETHENA_ARM")));

        EthenaAssetAdapter adapterImpl = new EthenaAssetAdapter(address(proxy), Mainnet.USDE, Mainnet.SUSDE);
        resolver.addContract("ETHENA_ARM_SUSDE_ADAPTER_IMPL", address(adapterImpl));
        Proxy adapterProxy = new Proxy();
        adapterProxy.initialize(address(adapterImpl), address(this), "");
        EthenaAssetAdapter adapter = EthenaAssetAdapter(address(adapterProxy));
        adapter.deployUnstakers();
        adapterProxy.setOwner(Mainnet.TIMELOCK);
        resolver.addContract("ETHENA_ARM_SUSDE_ADAPTER", address(adapterProxy));

        EthenaARM arm = EthenaARM(payable(address(proxy)));
        vm.startPrank(arm.owner());
        _addBaseAssetIfMissing(arm, Mainnet.SUSDE, address(adapterProxy), 0.998e36, 1e36, 0.99996e36, false);
        vm.stopPrank();
    }

    function _upgradeOriginARM() internal {
        Proxy proxy = Proxy(payable(resolver.resolve("OETH_ARM")));
        OriginARM impl = new OriginARM(Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT, 10 minutes, 1e7, 1e18);
        resolver.addContract("OETH_ARM_IMPL", address(impl));

        _clearLegacyPendingAmount(address(proxy));

        vm.prank(proxy.owner());
        proxy.upgradeTo(address(impl));

        _clearLegacyWithdrawQueueForSmoke(address(proxy));
        _migrateLegacyWithdrawQueue(address(proxy));

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

    function _clearLegacyWithdrawQueueForSmoke(address arm) internal {
        // The live fork can contain outstanding legacy LP withdrawals at the selected block.
        // Smoke tests normalize that fork-only state so the strict production migration path can run.
        stdstore.target(arm).sig("reservedWithdrawLiquidity()").checked_write(uint256(0));
    }

    function _migrateLegacyWithdrawQueue(address arm) internal {
        (bool success, bytes memory result) = arm.staticcall(abi.encodeWithSignature("owner()"));
        require(success, "owner lookup failed");

        vm.prank(abi.decode(result, (address)));
        (success, result) = arm.call(abi.encodeWithSignature("migrateLegacyWithdrawQueue()"));
        if (!success && result.length == 4 && bytes4(result) == INVALID_INITIALIZATION) return;
        if (!success) assembly {
            revert(add(result, 0x20), mload(result))
        }
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
        (,,,,,,, address configuredAdapter) = arm.baseAssetConfigs(baseAsset);
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
        (,,,,,,, address configuredAdapter) = arm.baseAssetConfigs(baseAsset);
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
        (,,,,,,, address configuredAdapter) = arm.baseAssetConfigs(baseAsset);
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
        (,,,,,,, address configuredAdapter) = arm.baseAssetConfigs(baseAsset);
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
}
