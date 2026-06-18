// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {CapManager} from "contracts/CapManager.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {Proxy} from "contracts/Proxy.sol";
import {StablesARM} from "contracts/StablesARM.sol";
import {PaxosAssetAdapter} from "contracts/adapters/PaxosAssetAdapter.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {$034_DeployStablesARMScript} from "script/deploy/mainnet/034_DeployStablesARMScript.s.sol";
import {Resolver} from "script/deploy/helpers/Resolver.sol";
import {State} from "script/deploy/helpers/DeploymentTypes.sol";

contract Fork_StablesARM_Smoke_Test is Test {
    IERC20 usdc;
    IERC20 usdg;
    IERC20 pyusd;
    Proxy armProxy;
    StablesARM stablesARM;
    PaxosAssetAdapter usdgAdapter;
    PaxosAssetAdapter pyusdAdapter;
    CapManager capManager;
    address paxosRecipient;
    Resolver internal resolver = Resolver(address(uint160(uint256(keccak256("Resolver")))));

    function setUp() public {
        require(vm.envExists("MAINNET_URL"), "MAINNET_URL not set");

        if (vm.envExists("FORK_BLOCK_NUMBER_MAINNET")) {
            vm.createSelectFork(vm.envString("MAINNET_URL"), vm.envUint("FORK_BLOCK_NUMBER_MAINNET"));
        } else {
            vm.createSelectFork(vm.envString("MAINNET_URL"));
        }

        bytes memory resolverCode = vm.getDeployedCode("Resolver.sol:Resolver");
        vm.etch(address(resolver), resolverCode);
        resolver.setState(State.FORK_TEST);

        address deployer = address(0x1);
        if (vm.envExists("DEPLOYER_ADDRESS")) deployer = vm.envAddress("DEPLOYER_ADDRESS");
        deal(Mainnet.USDC, deployer, 1000);

        new $034_DeployStablesARMScript().run();

        usdc = IERC20(Mainnet.USDC);
        usdg = IERC20(Mainnet.USDG);
        pyusd = IERC20(Mainnet.PYUSD);
        armProxy = Proxy(payable(resolver.resolve("STABLES_ARM")));
        stablesARM = StablesARM(payable(resolver.resolve("STABLES_ARM")));
        capManager = CapManager(resolver.resolve("STABLES_ARM_CAP_MAN"));
        usdgAdapter = PaxosAssetAdapter(resolver.resolve("STABLES_ARM_USDG_ADAPTER"));
        pyusdAdapter = PaxosAssetAdapter(resolver.resolve("STABLES_ARM_PYUSD_ADAPTER"));
        paxosRecipient = makeAddr("paxosRecipient");

        vm.label(address(usdc), "USDC");
        vm.label(address(usdg), "USDG");
        vm.label(address(pyusd), "PYUSD");
        vm.label(address(stablesARM), "STABLES ARM");
        vm.label(address(usdgAdapter), "USDG PAXOS ADAPTER");
        vm.label(address(pyusdAdapter), "PYUSD PAXOS ADAPTER");
    }

    function test_initialConfig() external view {
        assertEq(stablesARM.name(), "StablesARM", "Name");
        assertEq(stablesARM.symbol(), "ARM-USDC-Stables", "Symbol");
        assertEq(stablesARM.decimals(), 6, "decimals");
        assertEq(stablesARM.minTotalSupply(), 1000, "min total supply");
        assertEq(stablesARM.owner(), Mainnet.GOV_MULTISIG, "Owner");
        assertEq(stablesARM.operator(), Mainnet.ARM_TALOS_RELAYER, "Operator");
        assertEq(stablesARM.feeCollector(), Mainnet.BUYBACK_OPERATOR, "Fee collector");
        assertEq(stablesARM.fee(), 2000, "fee");
        assertEq(stablesARM.liquidityAsset(), Mainnet.USDC, "liquidity asset");
        assertEq(stablesARM.asset(), Mainnet.USDC, "ERC-4626 asset");
        assertEq(stablesARM.claimDelay(), 10 minutes, "claim delay");

        assertEq(usdc.decimals(), 6, "USDC decimals");
        assertEq(usdg.decimals(), 6, "USDG decimals");
        assertEq(pyusd.decimals(), 6, "PYUSD decimals");

        assertEq(capManager.owner(), Mainnet.GOV_MULTISIG, "cap owner");
        assertEq(capManager.operator(), Mainnet.ARM_TALOS_RELAYER, "cap operator");
        assertEq(capManager.arm(), address(stablesARM), "cap arm");
        assertEq(capManager.totalAssetsCap(), 100_000e6, "total assets cap");
        assertEq(capManager.accountCapEnabled(), true, "account cap enabled");
        assertEq(capManager.liquidityProviderCaps(Mainnet.TREASURY_LP), 20_000e6, "treasury LP cap");

        assertEq(usdgAdapter.owner(), Mainnet.TIMELOCK, "USDG adapter owner");
        assertEq(usdgAdapter.operator(), Mainnet.ARM_TALOS_RELAYER, "USDG adapter operator");
        assertEq(usdgAdapter.asset(), Mainnet.USDC, "USDG adapter asset");
        assertEq(pyusdAdapter.owner(), Mainnet.TIMELOCK, "PYUSD adapter owner");
        assertEq(pyusdAdapter.operator(), Mainnet.ARM_TALOS_RELAYER, "PYUSD adapter operator");
        assertEq(pyusdAdapter.asset(), Mainnet.USDC, "PYUSD adapter asset");
    }

    function test_baseAssetConfig() external view {
        _assertBaseAssetConfig(Mainnet.USDG, address(usdgAdapter));
        _assertBaseAssetConfig(Mainnet.PYUSD, address(pyusdAdapter));
    }

    function test_usdgPaxosSettlementFlow() external {
        deal(Mainnet.USDG, address(stablesARM), 100e6);

        vm.prank(Mainnet.TIMELOCK);
        usdgAdapter.setPaxosRecipient(paxosRecipient);

        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        (uint256 sharesRequested, uint256 assetsExpected) = stablesARM.requestBaseAssetRedeem(Mainnet.USDG, 100e6);
        assertEq(sharesRequested, 100e6, "shares requested");
        assertEq(assetsExpected, 100e6, "assets expected");

        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        usdgAdapter.submitPaxosRedeem(100e6, keccak256("USDG-PAXOS-REDEMPTION"));
        assertEq(usdg.balanceOf(paxosRecipient), 100e6, "paxos USDG");
        assertEq(usdgAdapter.settlingShares(), 100e6, "settling shares");

        deal(Mainnet.USDC, address(usdgAdapter), 100e6);

        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        (uint256 sharesClaimed,, uint256 assetsReceived) = stablesARM.claimBaseAssetRedeem(Mainnet.USDG, 100e6);
        assertEq(sharesClaimed, 100e6, "shares claimed");
        assertEq(assetsReceived, 100e6, "assets received");
        assertEq(usdgAdapter.settlingShares(), 0, "settling claimed");
    }

    function test_pyusdPaxosSettlementFlow() external {
        deal(Mainnet.PYUSD, address(stablesARM), 100e6);

        vm.prank(Mainnet.TIMELOCK);
        pyusdAdapter.setPaxosRecipient(paxosRecipient);

        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        stablesARM.requestBaseAssetRedeem(Mainnet.PYUSD, 100e6);

        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        pyusdAdapter.submitPaxosRedeem(100e6, keccak256("PYUSD-PAXOS-REDEMPTION"));
        assertEq(pyusd.balanceOf(paxosRecipient), 100e6, "paxos PYUSD");

        deal(Mainnet.USDC, address(pyusdAdapter), 100e6);

        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        (,, uint256 assetsReceived) = stablesARM.claimBaseAssetRedeem(Mainnet.PYUSD, 100e6);
        assertEq(assetsReceived, 100e6, "assets received");
    }

    function _assertBaseAssetConfig(address baseAsset, address adapter) internal view {
        (
            uint128 buyPrice,
            uint128 sellPrice,
            uint128 buyLiquidity,
            uint128 sellLiquidity,
            uint128 crossPrice,
            uint120 pendingRedeemAssets,
            bool peggedToLiquidityAsset,
            address configuredAdapter
        ) = stablesARM.baseAssetConfigs(baseAsset);

        assertEq(buyPrice, 0.998e36, "buy price");
        assertEq(sellPrice, 1e36, "sell price");
        assertEq(buyLiquidity, type(uint128).max, "buy liquidity");
        assertEq(sellLiquidity, type(uint128).max, "sell liquidity");
        assertEq(crossPrice, 0.999e36, "cross price");
        assertEq(pendingRedeemAssets, 0, "pending redeem assets");
        assertEq(peggedToLiquidityAsset, true, "pegged");
        assertEq(configuredAdapter, adapter, "adapter");
    }
}
