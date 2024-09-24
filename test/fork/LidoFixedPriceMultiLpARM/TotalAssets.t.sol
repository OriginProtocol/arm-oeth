// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {MultiLP} from "contracts/MultiLP.sol";
import {PerformanceFee} from "contracts/PerformanceFee.sol";

contract Fork_Concrete_LidoFixedPriceMultiLpARM_TotalAssets_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        // Set Cap to max, as not to interfere with the tests
        address[] memory providers = new address[](1);
        providers[0] = address(this);
        liquidityProviderController.setLiquidityProviderCaps(providers, type(uint256).max);
        liquidityProviderController.setTotalAssetsCap(type(uint256).max);

        // Approve STETH for Lido
        lidoFixedPriceMulltiLpARM.approveStETH();
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TEST
    //////////////////////////////////////////////////////
    function test_TotalAssets_AfterInitialization() public {
        assertEq(lidoFixedPriceMulltiLpARM.totalAssets(), MIN_TOTAL_SUPPLY);
    }

    function test_TotalAssets_AfterDeposit_NoAssetGainOrLoss()
        public
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        assertEq(lidoFixedPriceMulltiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
    }

    function test_TotalAssets_AfterDeposit_WithAssetGain_InWETH()
        public
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        // Simulate asset gain
        uint256 assetGain = DEFAULT_AMOUNT / 2;
        deal(
            address(weth),
            address(lidoFixedPriceMulltiLpARM),
            weth.balanceOf(address(lidoFixedPriceMulltiLpARM)) + assetGain
        );

        // Calculate Fees
        uint256 fee = assetGain * 20 / 100; // 20% fee

        assertEq(lidoFixedPriceMulltiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT + assetGain - fee);
    }

    function test_TotalAssets_AfterDeposit_WithAssetGain_InSTETH()
        public
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        // Simulate asset gain
        uint256 assetGain = DEFAULT_AMOUNT / 2 + 1;
        // We are sure that steth balance is empty, so we can deal directly final amount.
        deal(address(steth), address(lidoFixedPriceMulltiLpARM), assetGain);

        // Calculate Fees
        uint256 fee = assetGain * 20 / 100; // 20% fee

        assertApproxEqAbs(
            lidoFixedPriceMulltiLpARM.totalAssets(),
            MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT + assetGain - fee,
            STETH_ERROR_ROUNDING
        );
    }

    function test_TotalAssets_AfterDeposit_WithAssetLoss_InWETH()
        public
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        // Simulate asset loss
        uint256 assetLoss = DEFAULT_AMOUNT / 2;
        deal(
            address(weth),
            address(lidoFixedPriceMulltiLpARM),
            weth.balanceOf(address(lidoFixedPriceMulltiLpARM)) - assetLoss
        );

        assertEq(lidoFixedPriceMulltiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT - assetLoss);
    }

    function test_TotalAssets_AfterDeposit_WithAssetLoss_InSTETH()
        public
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        // Simulate Swap at 1:1 between WETH and stETH
        uint256 swapAmount = DEFAULT_AMOUNT / 2;
        deal(
            address(weth),
            address(lidoFixedPriceMulltiLpARM),
            weth.balanceOf(address(lidoFixedPriceMulltiLpARM)) - swapAmount
        );
        // Then simulate a loss on stETH, do all in the same deal
        uint256 assetLoss = swapAmount / 2;
        deal(address(steth), address(lidoFixedPriceMulltiLpARM), swapAmount / 2);

        assertApproxEqAbs(
            lidoFixedPriceMulltiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT - assetLoss, STETH_ERROR_ROUNDING
        );
    }

    function test_TotalAssets_After_WithdrawingFromLido() public {
        // Simulate a Swap at 1:1 between WETH and stETH using initial liquidity
        uint256 swapAmount = MIN_TOTAL_SUPPLY / 2;
        deal(
            address(weth),
            address(lidoFixedPriceMulltiLpARM),
            weth.balanceOf(address(lidoFixedPriceMulltiLpARM)) - swapAmount
        );
        deal(address(steth), address(lidoFixedPriceMulltiLpARM), swapAmount); // Empty stETH balance, so we can deal directly

        uint256 totalAssetsBefore = lidoFixedPriceMulltiLpARM.totalAssets();

        // Request a redeem on Lido
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = swapAmount;
        lidoFixedPriceMulltiLpARM.requestStETHWithdrawalForETH(amounts);

        // Check total assets after withdrawal is the same as before
        assertApproxEqAbs(lidoFixedPriceMulltiLpARM.totalAssets(), totalAssetsBefore, STETH_ERROR_ROUNDING);
    }
}
