// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {stdError} from "forge-std/StdError.sol";

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
        lidoFixedPriceMultiLpARM.approveStETH();

        deal(address(weth), address(this), 1_000 ether);
        weth.approve(address(lidoFixedPriceMultiLpARM), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TEST
    //////////////////////////////////////////////////////
    function test_RevertWhen_TotalAssets_Because_MathError()
        public
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        simulateAssetGainInLidoFixedPriceMultiLpARM(DEFAULT_AMOUNT, address(weth), true)
        requestRedeemFromLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        simulateAssetGainInLidoFixedPriceMultiLpARM(DEFAULT_AMOUNT * 2, address(weth), false)
    {
        vm.expectRevert(stdError.arithmeticError);
        lidoFixedPriceMultiLpARM.totalAssets();
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TEST
    //////////////////////////////////////////////////////
    function test_TotalAssets_AfterInitialization() public view {
        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY);
    }

    function test_TotalAssets_AfterDeposit_NoAssetGainOrLoss()
        public
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
    }

    function test_TotalAssets_AfterDeposit_WithAssetGain_InWETH()
        public
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        // Simulate asset gain
        uint256 assetGain = DEFAULT_AMOUNT / 2;
        deal(
            address(weth),
            address(lidoFixedPriceMultiLpARM),
            weth.balanceOf(address(lidoFixedPriceMultiLpARM)) + assetGain
        );

        // Calculate Fees
        uint256 fee = assetGain * 20 / 100; // 20% fee

        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT + assetGain - fee);
    }

    function test_TotalAssets_AfterDeposit_WithAssetGain_InSTETH()
        public
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        // Simulate asset gain
        uint256 assetGain = DEFAULT_AMOUNT / 2 + 1;
        // We are sure that steth balance is empty, so we can deal directly final amount.
        deal(address(steth), address(lidoFixedPriceMultiLpARM), assetGain);

        // Calculate Fees
        uint256 fee = assetGain * 20 / 100; // 20% fee

        assertApproxEqAbs(
            lidoFixedPriceMultiLpARM.totalAssets(),
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
            address(lidoFixedPriceMultiLpARM),
            weth.balanceOf(address(lidoFixedPriceMultiLpARM)) - assetLoss
        );

        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT - assetLoss);
    }

    function test_TotalAssets_AfterDeposit_WithAssetLoss_InSTETH()
        public
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        // Simulate Swap at 1:1 between WETH and stETH
        uint256 swapAmount = DEFAULT_AMOUNT / 2;
        deal(
            address(weth),
            address(lidoFixedPriceMultiLpARM),
            weth.balanceOf(address(lidoFixedPriceMultiLpARM)) - swapAmount
        );
        // Then simulate a loss on stETH, do all in the same deal
        uint256 assetLoss = swapAmount / 2;
        deal(address(steth), address(lidoFixedPriceMultiLpARM), swapAmount / 2);

        assertApproxEqAbs(
            lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT - assetLoss, STETH_ERROR_ROUNDING
        );
    }

    function test_TotalAssets_After_WithdrawingFromLido() public {
        // Simulate a Swap at 1:1 between WETH and stETH using initial liquidity
        uint256 swapAmount = MIN_TOTAL_SUPPLY / 2;
        deal(
            address(weth),
            address(lidoFixedPriceMultiLpARM),
            weth.balanceOf(address(lidoFixedPriceMultiLpARM)) - swapAmount
        );
        deal(address(steth), address(lidoFixedPriceMultiLpARM), swapAmount); // Empty stETH balance, so we can deal directly

        uint256 totalAssetsBefore = lidoFixedPriceMultiLpARM.totalAssets();

        // Request a redeem on Lido
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = swapAmount;
        lidoFixedPriceMultiLpARM.requestStETHWithdrawalForETH(amounts);

        // Check total assets after withdrawal is the same as before
        assertApproxEqAbs(lidoFixedPriceMultiLpARM.totalAssets(), totalAssetsBefore, STETH_ERROR_ROUNDING);
    }

    function test_TotalAssets_With_FeeAccrued_NotNull() public {
        uint256 assetGain = DEFAULT_AMOUNT;
        // Simulate asset gain
        deal(
            address(weth),
            address(lidoFixedPriceMultiLpARM),
            weth.balanceOf(address(lidoFixedPriceMultiLpARM)) + assetGain
        );

        // User deposit, this will trigger a fee calculation
        lidoFixedPriceMultiLpARM.deposit(DEFAULT_AMOUNT);

        // Assert fee accrued is not null
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), assetGain * 20 / 100);

        assertEq(
            lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT + assetGain - assetGain * 20 / 100
        );
    }

    function test_TotalAssets_When_ARMIsInsolvent()
        public
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        // Simulate a loss of assets
        deal(address(weth), address(lidoFixedPriceMultiLpARM), DEFAULT_AMOUNT - 1);

        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), 0);
    }
}
