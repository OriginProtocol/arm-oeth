// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {AbstractSmokeTest} from "./AbstractSmokeTest.sol";

import {AbstractARM} from "contracts/AbstractARM.sol";
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

contract Fork_WETHARM_Smoke_Test is AbstractSmokeTest {
    MultiAssetARM internal wethARM;
    CapManager internal capManager;

    function setUp() public override {
        super.setUp();

        wethARM = MultiAssetARM(payable(resolver.resolve("WETH_ARM")));
        capManager = CapManager(resolver.resolve("WETH_ARM_CAP_MAN"));
    }

    function test_InitialConfig() external view {
        assertEq(wethARM.name(), "WETH ARM", "name");
        assertEq(wethARM.symbol(), "ARM-WETH", "symbol");
        assertEq(wethARM.owner(), Mainnet.TIMELOCK, "owner");
        assertEq(wethARM.operator(), Mainnet.ARM_TALOS_RELAYER, "operator");
        assertEq(wethARM.feeCollector(), Mainnet.BUYBACK_OPERATOR, "fee collector");
        assertEq(wethARM.fee(), 2000, "performance fee");
        assertEq(wethARM.liquidityAsset(), Mainnet.WETH, "liquidity asset");
        assertEq(wethARM.claimDelay(), 10 minutes, "claim delay");

        assertEq(capManager.arm(), address(wethARM), "cap manager arm");
        assertEq(capManager.totalAssetsCap(), 250 ether, "total assets cap");
        assertTrue(capManager.accountCapEnabled(), "account cap enabled");
        assertEq(capManager.liquidityProviderCaps(Mainnet.TREASURY_LP), 245 ether, "liquidity provider cap");
        assertEq(capManager.operator(), Mainnet.MULTISIG_2_OF_8, "cap manager operator");
        assertEq(capManager.owner(), Mainnet.MULTISIG_2_OF_8, "cap manager owner");
    }

    function test_BaseAssetConfigs() external view {
        address[] memory baseAssets = wethARM.getBaseAssets();
        assertEq(baseAssets.length, 4, "base asset count");
        assertEq(baseAssets[0], Mainnet.STETH, "stETH order");
        assertEq(baseAssets[1], Mainnet.WSTETH, "wstETH order");
        assertEq(baseAssets[2], Mainnet.EETH, "eETH order");
        assertEq(baseAssets[3], Mainnet.WEETH, "weETH order");

        _assertBaseAssetConfig(Mainnet.STETH, "WETH_ARM_STETH_ADAPTER", true);
        _assertBaseAssetConfig(Mainnet.WSTETH, "WETH_ARM_WSTETH_ADAPTER", false);
        _assertBaseAssetConfig(Mainnet.EETH, "WETH_ARM_EETH_ADAPTER", true);
        _assertBaseAssetConfig(Mainnet.WEETH, "WETH_ARM_WEETH_ADAPTER", false);
    }

    function test_EtherFiAdapterUpgrades() external view {
        Proxy eethAdapter = Proxy(payable(resolver.resolve("WETH_ARM_EETH_ADAPTER")));
        Proxy weethAdapter = Proxy(payable(resolver.resolve("WETH_ARM_WEETH_ADAPTER")));

        assertEq(eethAdapter.owner(), Mainnet.TIMELOCK, "eETH adapter owner");
        assertEq(weethAdapter.owner(), Mainnet.TIMELOCK, "weETH adapter owner");
        assertEq(
            eethAdapter.implementation(), resolver.resolve("WETH_ARM_EETH_ADAPTER_IMPL"), "eETH adapter implementation"
        );
        assertEq(
            weethAdapter.implementation(),
            resolver.resolve("WETH_ARM_WEETH_ADAPTER_IMPL"),
            "weETH adapter implementation"
        );
    }

    function test_MorphoMarketConfig() external view {
        Abstract4626MarketWrapper morphoMarket = Abstract4626MarketWrapper(resolver.resolve("MORPHO_MARKET_WETH_ARM"));
        Abstract4626MarketWrapper lidoMarket = Abstract4626MarketWrapper(resolver.resolve("MORPHO_MARKET_LIDO"));
        address etherFiActiveMarket = MultiAssetARM(payable(resolver.resolve("ETHER_FI_ARM"))).activeMarket();
        Abstract4626MarketWrapper etherFiMarket = Abstract4626MarketWrapper(etherFiActiveMarket);

        assertEq(morphoMarket.arm(), address(wethARM), "market arm");
        assertEq(morphoMarket.asset(), Mainnet.WETH, "market asset");
        assertEq(morphoMarket.market(), Mainnet.MORPHO_WETH_VAULT, "configured Morpho vault");
        assertEq(morphoMarket.market(), lidoMarket.market(), "Lido Morpho vault");
        assertEq(morphoMarket.market(), etherFiMarket.market(), "EtherFi Morpho vault");
        assertEq(morphoMarket.owner(), Mainnet.TIMELOCK, "market owner");
        assertEq(morphoMarket.harvester(), Mainnet.MULTISIG_2_OF_8, "market harvester");
        assertEq(address(morphoMarket.merkleDistributor()), Mainnet.MERKLE_DISTRIBUTOR, "Merkle distributor");
        assertTrue(wethARM.supportedMarkets(address(morphoMarket)), "market supported");
        assertEq(wethARM.activeMarket(), address(morphoMarket), "active market");
    }

    //////////////////////////////////////////////////////
    /// --- pause roles
    //////////////////////////////////////////////////////

    /// @notice The 043 upgrade wires the 2/8 as guardian and the 5/8 as adminMultisig.
    function test_PauseRolesConfigured() external view {
        assertEq(wethARM.guardian(), Mainnet.MULTISIG_2_OF_8, "guardian is the 2/8");
        assertEq(wethARM.adminMultisig(), Mainnet.MULTISIG_5_OF_8, "adminMultisig is the 5/8");
    }

    /// @notice The 2/8 gets a no-delay pause, but must not be able to re-open the ARM. Together with
    ///         owner staying the upgrade admin, that stops any single 2/8 key from both unpausing and
    ///         changing the code.
    function test_GuardianCanPauseButNotUnpause() external {
        vm.prank(Mainnet.MULTISIG_2_OF_8);
        wethARM.pause();
        assertTrue(wethARM.paused(), "guardian paused");

        vm.prank(Mainnet.MULTISIG_2_OF_8);
        vm.expectRevert(AbstractARM.OnlyUnpauser.selector);
        wethARM.unpause();
        assertTrue(wethARM.paused(), "still paused after guardian tried to unpause");

        // The 5/8 recovers with no delay and no governance vote.
        vm.prank(Mainnet.MULTISIG_5_OF_8);
        wethARM.unpause();
        assertFalse(wethARM.paused(), "adminMultisig unpaused");
    }

    /// @notice The Talos relayer is a hot key: it keeps its pause, but never gains unpause.
    function test_OperatorCannotUnpause() external {
        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        wethARM.pause();
        assertTrue(wethARM.paused(), "operator paused");

        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        vm.expectRevert(AbstractARM.OnlyUnpauser.selector);
        wethARM.unpause();

        vm.prank(Mainnet.MULTISIG_5_OF_8);
        wethARM.unpause();
    }

    /// @notice Storage-layout proof. `guardian`/`adminMultisig` were taken from the AbstractARM gap
    ///         at slots 62 and 63. Read the live variables that bracket them and confirm they still
    ///         hold sane values: a layout shift shows up here first.
    function test_StorageLayoutPreservedAcrossUpgrade() external view {
        // Slots 59-61, immediately before the new roles.
        assertEq(wethARM.feeCollector(), Mainnet.BUYBACK_OPERATOR, "feeCollector (slot 59) intact");
        assertEq(
            uint256(vm.load(address(wethARM), bytes32(uint256(59)))),
            uint256(uint160(Mainnet.BUYBACK_OPERATOR)),
            "slot 59 raw"
        );
        assertGe(wethARM.withdrawsQueuedShares(), wethARM.withdrawsClaimedShares(), "slot 60 queue invariant");

        // The new roles themselves, at slots 62 and 63.
        assertEq(
            uint256(vm.load(address(wethARM), bytes32(uint256(62)))),
            uint256(uint160(Mainnet.MULTISIG_2_OF_8)),
            "guardian at slot 62"
        );
        assertEq(
            uint256(vm.load(address(wethARM), bytes32(uint256(63)))),
            uint256(uint160(Mainnet.MULTISIG_5_OF_8)),
            "adminMultisig at slot 63"
        );

        // Live accounting still reads back sane, so nothing downstream shifted either.
        assertGt(wethARM.totalAssets(), 0, "totalAssets intact");
        assertEq(wethARM.liquidityAsset(), Mainnet.WETH, "liquidityAsset intact");
        assertEq(wethARM.getBaseAssets().length, 4, "base assets intact");
    }

    function _assertBaseAssetConfig(address baseAsset, string memory adapterName, bool pegged) internal view {
        (,,,,,, bool peggedToLiquidityAsset, uint8 baseAssetDecimals, address adapter) =
            wethARM.baseAssetConfigs(baseAsset);

        assertEq(peggedToLiquidityAsset, pegged, "pegged");
        assertEq(baseAssetDecimals, 18, "base asset decimals");
        assertEq(adapter, resolver.resolve(adapterName), "adapter");
    }
}
