// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {stdError} from "forge-std/StdError.sol";

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

contract Fork_Concrete_LidoARM_TotalAssets_Test_ is Fork_Shared_Test_ {
    uint256 internal constant DISCOUNTED_PRICE = 9995e32; // 0.9995

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        // Set Cap to max, as not to interfere with the tests
        address[] memory providers = new address[](1);
        providers[0] = address(this);
        capManager.setLiquidityProviderCaps(providers, type(uint256).max);
        capManager.setTotalAssetsCap(type(uint248).max);

        deal(address(weth), address(this), 1_000 ether);
        weth.approve(address(lidoARM), type(uint256).max);
    }

    function _swapBaseForLiquidity(uint256 amountIn) internal returns (uint256 amountOut, uint256 expectedFee) {
        lidoARM.setPrices(DISCOUNTED_PRICE, 1001e33);
        deal(address(steth), address(this), amountIn);
        steth.approve(address(lidoARM), type(uint256).max);

        uint256[] memory amounts = lidoARM.swapExactTokensForTokens(steth, weth, amountIn, 0, address(this));
        amountOut = amounts[1];
        expectedFee = (amountIn - amountOut) * lidoARM.fee() / lidoARM.FEE_SCALE();
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TEST
    //////////////////////////////////////////////////////
    function test_TotalAssets_AfterInitialization() public view {
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY);
    }

    function test_TotalAssets_AfterDeposit_NoAssetGainOrLoss() public depositInLidoARM(address(this), DEFAULT_AMOUNT) {
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT - 1);
    }

    function test_TotalAssets_AfterDeposit_WithAssetGain_InWETH()
        public
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
    {
        // Simulate asset gain
        uint256 assetGain = DEFAULT_AMOUNT / 2;
        deal(address(weth), address(lidoARM), weth.balanceOf(address(lidoARM)) + assetGain);

        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT + assetGain - 1);
    }

    function test_TotalAssets_AfterDeposit_WithAssetGain_InSTETH()
        public
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
    {
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        // Simulate asset gain
        uint256 assetGain = DEFAULT_AMOUNT / 2 + 1;
        // We are sure that steth balance is empty, so we can deal directly final amount.
        deal(address(steth), address(lidoARM), assetGain);

        assertApproxEqAbs(
            lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT + assetGain - 1, STETH_ERROR_ROUNDING
        );
    }

    function test_TotalAssets_AfterDeposit_WithAssetLoss_InWETH()
        public
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
    {
        // Simulate asset loss
        uint256 assetLoss = DEFAULT_AMOUNT / 2;
        deal(address(weth), address(lidoARM), weth.balanceOf(address(lidoARM)) - assetLoss);

        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT - assetLoss - 1);
    }

    function test_TotalAssets_AfterDeposit_WithAssetLoss_InSTETH()
        public
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
    {
        // Simulate Swap at 1:1 between WETH and stETH
        uint256 swapAmount = DEFAULT_AMOUNT / 2;
        deal(address(weth), address(lidoARM), weth.balanceOf(address(lidoARM)) - swapAmount);
        // Then simulate a loss on stETH, do all in the same deal
        uint256 assetLoss = swapAmount / 2;
        deal(address(steth), address(lidoARM), swapAmount / 2);

        assertApproxEqAbs(
            lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT - assetLoss - 1, STETH_ERROR_ROUNDING
        );
    }

    function test_TotalAssets_After_WithdrawingFromLido() public {
        // Simulate a Swap at 1:1 between WETH and stETH using initial liquidity
        uint256 swapAmount = MIN_TOTAL_SUPPLY / 2;
        deal(address(weth), address(lidoARM), weth.balanceOf(address(lidoARM)) - swapAmount);
        deal(address(steth), address(lidoARM), swapAmount); // Empty stETH balance, so we can deal directly

        uint256 totalAssetsBefore = lidoARM.totalAssets();

        // Request a redeem on Lido
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = swapAmount;
        lidoARM.requestLidoWithdrawals(amounts);

        // Check total assets after withdrawal is the same as before
        assertApproxEqAbs(lidoARM.totalAssets(), totalAssetsBefore, STETH_ERROR_ROUNDING);
    }

    function test_TotalAssets_With_FeeAccrued_NotNull() public {
        lidoARM.deposit(DEFAULT_AMOUNT);
        deal(address(weth), address(lidoARM), 200 ether);
        uint256 totalAssetsBefore = lidoARM.totalAssets();

        (uint256 amountOut, uint256 expectedFee) = _swapBaseForLiquidity(100 ether);

        // Assert fee accrued on discounted swap only.
        assertEq(lidoARM.feesAccrued(), expectedFee + 1);
        assertApproxEqAbs(lidoARM.totalAssets(), totalAssetsBefore + 100 ether - amountOut - expectedFee - 1, 1);
    }

    function test_TotalAssets_When_ARMIsInsolvent()
        public
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoARM(address(this), DEFAULT_AMOUNT)
    {
        // Simulate a loss of assets
        deal(address(weth), address(lidoARM), DEFAULT_AMOUNT - 1);

        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY);
    }

    function test_RevertWhen_TotalAssets_Because_MathError()
        public
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
        simulateAssetGainInLidoARM(DEFAULT_AMOUNT, address(weth), true)
        requestRedeemFromLidoARM(address(this), DEFAULT_AMOUNT)
        simulateAssetGainInLidoARM(DEFAULT_AMOUNT * 2, address(weth), false)
    {
        // vm.expectRevert(stdError.arithmeticError);
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY);
    }

    function test_TotalAssets_FullLossOrARM() public depositInLidoARM(address(this), DEFAULT_AMOUNT) {
        // Simulate a loss of assets
        deal(address(weth), address(lidoARM), 0);

        // Assert total assets is equal to the minimum total supply, even if the ARM is empty.
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY);
    }
}
