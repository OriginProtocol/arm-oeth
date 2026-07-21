// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AbstractSmokeTest} from "./AbstractSmokeTest.sol";

import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

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
        assertEq(wethARM.owner(), Mainnet.MULTISIG_2_OF_8, "owner");
        assertEq(wethARM.operator(), Mainnet.ARM_TALOS_RELAYER, "operator");
        assertEq(wethARM.feeCollector(), Mainnet.BUYBACK_OPERATOR, "fee collector");
        assertEq(wethARM.fee(), 2000, "performance fee");
        assertEq(wethARM.liquidityAsset(), Mainnet.WETH, "liquidity asset");
        assertEq(wethARM.claimDelay(), 10 minutes, "claim delay");

        assertEq(capManager.arm(), address(wethARM), "cap manager arm");
        assertEq(capManager.totalAssetsCap(), 250 ether, "total assets cap");
        assertTrue(capManager.accountCapEnabled(), "account cap enabled");
        assertEq(capManager.liquidityProviderCaps(Mainnet.TREASURY_LP), 250 ether, "liquidity provider cap");
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

    function _assertBaseAssetConfig(address baseAsset, string memory adapterName, bool pegged) internal view {
        (
            uint128 buyPrice,
            uint128 sellPrice,
            uint128 buyLiquidityRemaining,
            uint128 sellLiquidityRemaining,
            uint128 crossPrice,
            uint128 pendingRedeemAssets,
            bool peggedToLiquidityAsset,
            uint8 baseAssetDecimals,
            address adapter
        ) = wethARM.baseAssetConfigs(baseAsset);

        assertEq(buyPrice, 0.9997e36, "buy price");
        assertEq(sellPrice, 1e36, "sell price");
        assertEq(buyLiquidityRemaining, type(uint128).max, "buy liquidity");
        assertEq(sellLiquidityRemaining, type(uint128).max, "sell liquidity");
        assertEq(crossPrice, 0.99996e36, "cross price");
        assertEq(pendingRedeemAssets, 0, "pending redeem assets");
        assertEq(peggedToLiquidityAsset, pegged, "pegged");
        assertEq(baseAssetDecimals, 18, "base asset decimals");
        assertEq(adapter, resolver.resolve(adapterName), "adapter");
    }
}
