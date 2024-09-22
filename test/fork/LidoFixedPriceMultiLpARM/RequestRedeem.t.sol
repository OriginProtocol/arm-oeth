// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

contract Fork_Concrete_LidoFixedPriceMultiLpARM_RequestRedeem_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        deal(address(weth), address(this), 1_000 ether);
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_RequestRedeem_SimpleCase()
        public
        asLidoFixedPriceMultiLpARMOwner
        setLiquidityProviderCap(address(this), 20 ether)
    {
        deal(address(weth), address(this), 10 ether);

        lidoFixedPriceMulltiLpARM.deposit(10 ether);
        lidoFixedPriceMulltiLpARM.requestRedeem(8 ether);
    }

    /// @notice Test the `requestRedeem` function when there are no profits and the first deposit is made.
    function test_RequestWithdraw_AfterFirstDeposit_NoPerfs_EmptyWithdrawQueue()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        // Assertions Before
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), DEFAULT_AMOUNT);
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(0, 0, 0, 0);

        // Main Call
        (uint256 requestId, uint256 assets) = lidoFixedPriceMulltiLpARM.requestRedeem(DEFAULT_AMOUNT);

        assertEq(requestId, 0); // First request
        assertEq(assets, DEFAULT_AMOUNT, "Wrong amount of assets"); // As no profits, assets returned are the same as deposited
    }
}
