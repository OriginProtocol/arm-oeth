// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {MultiLP} from "contracts/MultiLP.sol";
import {PerformanceFee} from "contracts/PerformanceFee.sol";

contract Fork_Concrete_LidoFixedPriceMultiLpARM_ClaimRedeem_Test_ is Fork_Shared_Test_ {
    uint256 private delay;
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////

    function setUp() public override {
        super.setUp();

        delay = lidoFixedPriceMulltiLpARM.CLAIM_DELAY();

        deal(address(weth), address(this), 1_000 ether);
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_ClaimRequest_Because_ClaimDelayNotMet()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        skip(delay - 1);
        vm.expectRevert("Claim delay not met");
        lidoFixedPriceMulltiLpARM.claimRedeem(0);
    }

    function test_RevertWhen_ClaimRequest_Because_QueuePendingLiquidity_NoLiquidity()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        // Remove all weth liquidity from ARM
        deal(address(weth), address(lidoFixedPriceMulltiLpARM), 0);

        // Time jump claim delay
        skip(delay);

        // Expect revert
        vm.expectRevert("Queue pending liquidity");
        lidoFixedPriceMulltiLpARM.claimRedeem(0);
    }

    function test_RevertWhen_ClaimRequest_Because_QueuePendingLiquidity_NoEnoughLiquidity()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        // Remove half of weth liquidity from ARM
        uint256 halfAmount = weth.balanceOf(address(lidoFixedPriceMulltiLpARM)) / 2;
        deal(address(weth), address(lidoFixedPriceMulltiLpARM), halfAmount);

        // Time jump claim delay
        skip(delay);

        // Expect revert
        vm.expectRevert("Queue pending liquidity");
        lidoFixedPriceMulltiLpARM.claimRedeem(0);
    }

    function test_RevertWhen_ClaimRequest_Because_NotRequester()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        // Time jump claim delay
        skip(delay);

        // Expect revert
        vm.startPrank(vm.randomAddress());
        vm.expectRevert("Not requester");
        lidoFixedPriceMulltiLpARM.claimRedeem(0);
    }

    function test_RevertWhen_ClaimRequest_Because_AlreadyClaimed()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        skipTime(delay)
        claimRequestOnLidoFixedPriceMultiLpARM(address(this), 0)
    {
        // Expect revert
        vm.expectRevert("Already claimed");
        lidoFixedPriceMulltiLpARM.claimRedeem(0);
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////

    function test_ClaimRequest_MoreThanEnoughLiquidity_()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        skipTime(delay)
    {
        // Assertions before
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), 0);
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(DEFAULT_AMOUNT, 0, 0, 1);
        assertEqUserRequest(0, address(this), false, block.timestamp, DEFAULT_AMOUNT, DEFAULT_AMOUNT);

        // Expected events
        vm.expectEmit({emitter: address(lidoFixedPriceMulltiLpARM)});
        emit MultiLP.RedeemClaimed(address(this), 0, DEFAULT_AMOUNT);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoFixedPriceMulltiLpARM), address(this), DEFAULT_AMOUNT);

        // Main call
        (uint256 assets) = lidoFixedPriceMulltiLpARM.claimRedeem(0);

        // Assertions after
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), 0);
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(DEFAULT_AMOUNT, DEFAULT_AMOUNT, DEFAULT_AMOUNT, 1);
        assertEqUserRequest(0, address(this), true, block.timestamp, DEFAULT_AMOUNT, DEFAULT_AMOUNT);
        assertEq(assets, DEFAULT_AMOUNT);
    }

    function test_ClaimRequest_JustEnoughLiquidity_()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        skipTime(delay)
    {
        // Assertions before
        // Same situation as above

        // Swap MIN_TOTAL_SUPPLY from WETH in STETH
        deal(address(weth), address(lidoFixedPriceMulltiLpARM), DEFAULT_AMOUNT);
        deal(address(steth), address(lidoFixedPriceMulltiLpARM), MIN_TOTAL_SUPPLY);

        // Handle lido rounding issue to ensure that balance is exactly MIN_TOTAL_SUPPLY
        if (steth.balanceOf(address(lidoFixedPriceMulltiLpARM)) == MIN_TOTAL_SUPPLY - 1) {
            deal(address(steth), address(lidoFixedPriceMulltiLpARM), 0);
            deal(address(steth), address(lidoFixedPriceMulltiLpARM), MIN_TOTAL_SUPPLY + 1);
        }

        // Expected events
        vm.expectEmit({emitter: address(lidoFixedPriceMulltiLpARM)});
        emit MultiLP.RedeemClaimed(address(this), 0, DEFAULT_AMOUNT);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoFixedPriceMulltiLpARM), address(this), DEFAULT_AMOUNT);

        // Main call
        (uint256 assets) = lidoFixedPriceMulltiLpARM.claimRedeem(0);

        // Assertions after
        assertApproxEqAbs(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY, 1);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), 0);
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(DEFAULT_AMOUNT, DEFAULT_AMOUNT, DEFAULT_AMOUNT, 1);
        assertEqUserRequest(0, address(this), true, block.timestamp, DEFAULT_AMOUNT, DEFAULT_AMOUNT);
        assertEq(assets, DEFAULT_AMOUNT);
    }

    function test_ClaimRequest_SecondClaim()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT / 2)
        skipTime(delay)
        claimRequestOnLidoFixedPriceMultiLpARM(address(this), 0)
        requestRedeemFromLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT / 2)
    {
        // Assertions before
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT / 2);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), 0);
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(DEFAULT_AMOUNT, DEFAULT_AMOUNT / 2, DEFAULT_AMOUNT / 2, 2);
        assertEqUserRequest(0, address(this), true, block.timestamp, DEFAULT_AMOUNT / 2, DEFAULT_AMOUNT / 2);
        assertEqUserRequest(1, address(this), false, block.timestamp + delay, DEFAULT_AMOUNT / 2, DEFAULT_AMOUNT);

        // Expected events
        vm.expectEmit({emitter: address(lidoFixedPriceMulltiLpARM)});
        emit MultiLP.RedeemClaimed(address(this), 1, DEFAULT_AMOUNT / 2);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoFixedPriceMulltiLpARM), address(this), DEFAULT_AMOUNT / 2);

        // Main call
        skip(delay);
        (uint256 assets) = lidoFixedPriceMulltiLpARM.claimRedeem(1);

        // Assertions after
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), 0);
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(DEFAULT_AMOUNT, DEFAULT_AMOUNT, DEFAULT_AMOUNT, 2);
        assertEqUserRequest(0, address(this), true, block.timestamp - delay, DEFAULT_AMOUNT / 2, DEFAULT_AMOUNT / 2);
        assertEqUserRequest(1, address(this), true, block.timestamp, DEFAULT_AMOUNT / 2, DEFAULT_AMOUNT);
        assertEq(assets, DEFAULT_AMOUNT / 2);
    }
}