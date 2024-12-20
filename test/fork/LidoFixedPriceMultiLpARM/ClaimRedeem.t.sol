// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

contract Fork_Concrete_LidoARM_ClaimRedeem_Test_ is Fork_Shared_Test_ {
    bool private ac;
    uint256 private delay;
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////

    function setUp() public override {
        super.setUp();

        delay = lidoARM.claimDelay();

        deal(address(weth), address(this), 1_000 ether);

        ac = capManager.accountCapEnabled();
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_ClaimRequest_Because_ClaimDelayNotMet()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoARM(address(this), DEFAULT_AMOUNT)
    {
        skip(delay - 1);
        vm.expectRevert("Claim delay not met");
        lidoARM.claimRedeem(0);
    }

    function test_RevertWhen_ClaimRequest_Because_QueuePendingLiquidity_NoLiquidity()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoARM(address(this), DEFAULT_AMOUNT)
    {
        // Remove all weth liquidity from ARM
        deal(address(weth), address(lidoARM), 0);

        // Time jump claim delay
        skip(delay);

        // Expect revert
        vm.expectRevert("Queue pending liquidity");
        lidoARM.claimRedeem(0);
    }

    function test_RevertWhen_ClaimRequest_Because_QueuePendingLiquidity_NoEnoughLiquidity()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoARM(address(this), DEFAULT_AMOUNT)
    {
        // Remove half of weth liquidity from ARM
        uint256 halfAmount = weth.balanceOf(address(lidoARM)) / 2;
        deal(address(weth), address(lidoARM), halfAmount);

        // Time jump claim delay
        skip(delay);

        // Expect revert
        vm.expectRevert("Queue pending liquidity");
        lidoARM.claimRedeem(0);
    }

    function test_RevertWhen_ClaimRequest_Because_NotRequester()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoARM(address(this), DEFAULT_AMOUNT)
    {
        // Time jump claim delay
        skip(delay);

        // Expect revert
        vm.startPrank(vm.randomAddress());
        vm.expectRevert("Not requester");
        lidoARM.claimRedeem(0);
    }

    function test_RevertWhen_ClaimRequest_Because_AlreadyClaimed()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoARM(address(this), DEFAULT_AMOUNT)
        skipTime(delay)
        claimRequestOnLidoARM(address(this), 0)
    {
        // Expect revert
        vm.expectRevert("Already claimed");
        lidoARM.claimRedeem(0);
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////

    function test_ClaimRequest_MoreThanEnoughLiquidity_()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoARM(address(this), DEFAULT_AMOUNT)
        skipTime(delay)
    {
        // Assertions before
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY));
        assertEq(lidoARM.balanceOf(address(this)), 0);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY);
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(DEFAULT_AMOUNT, 0, 1);
        assertEqUserRequest(0, address(this), false, block.timestamp, DEFAULT_AMOUNT, DEFAULT_AMOUNT);
        assertEq(lidoARM.claimable(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), address(this), DEFAULT_AMOUNT);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.RedeemClaimed(address(this), 0, DEFAULT_AMOUNT);

        // Main call
        (uint256 assets) = lidoARM.claimRedeem(0);

        // Assertions after
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY));
        assertEq(lidoARM.balanceOf(address(this)), 0);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY);
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(DEFAULT_AMOUNT, DEFAULT_AMOUNT, 1);
        assertEqUserRequest(0, address(this), true, block.timestamp, DEFAULT_AMOUNT, DEFAULT_AMOUNT);
        assertEq(assets, DEFAULT_AMOUNT);
        assertEq(lidoARM.claimable(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
    }

    function test_ClaimRequest_JustEnoughLiquidity_()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoARM(address(this), DEFAULT_AMOUNT)
        skipTime(delay)
    {
        // Assertions before
        // Same situation as above

        // Swap MIN_TOTAL_SUPPLY from WETH in STETH
        deal(address(weth), address(lidoARM), DEFAULT_AMOUNT);
        deal(address(steth), address(lidoARM), MIN_TOTAL_SUPPLY);

        // Handle lido rounding issue to ensure that balance is exactly MIN_TOTAL_SUPPLY
        if (steth.balanceOf(address(lidoARM)) == MIN_TOTAL_SUPPLY - 1) {
            deal(address(steth), address(lidoARM), 0);
            deal(address(steth), address(lidoARM), MIN_TOTAL_SUPPLY + 1);
        }

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), address(this), DEFAULT_AMOUNT);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.RedeemClaimed(address(this), 0, DEFAULT_AMOUNT);

        // Main call
        (uint256 assets) = lidoARM.claimRedeem(0);

        // Assertions after
        assertApproxEqAbs(steth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY, 2);
        assertEq(weth.balanceOf(address(lidoARM)), 0);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY));
        assertEq(lidoARM.balanceOf(address(this)), 0);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY);
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(DEFAULT_AMOUNT, DEFAULT_AMOUNT, 1);
        assertEqUserRequest(0, address(this), true, block.timestamp, DEFAULT_AMOUNT, DEFAULT_AMOUNT);
        assertEq(assets, DEFAULT_AMOUNT);
    }

    function test_ClaimRequest_SecondClaim()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoARM(address(this), DEFAULT_AMOUNT / 2)
        skipTime(delay)
        claimRequestOnLidoARM(address(this), 0)
        requestRedeemFromLidoARM(address(this), DEFAULT_AMOUNT / 2)
    {
        // Assertions before
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT / 2);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY));
        assertEq(lidoARM.balanceOf(address(this)), 0);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY);
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(DEFAULT_AMOUNT, DEFAULT_AMOUNT / 2, 2);
        assertEqUserRequest(0, address(this), true, block.timestamp, DEFAULT_AMOUNT / 2, DEFAULT_AMOUNT / 2);
        assertEqUserRequest(1, address(this), false, block.timestamp + delay, DEFAULT_AMOUNT / 2, DEFAULT_AMOUNT);
        assertEq(lidoARM.claimable(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), address(this), DEFAULT_AMOUNT / 2);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.RedeemClaimed(address(this), 1, DEFAULT_AMOUNT / 2);

        // Main call
        skip(delay);
        (uint256 assets) = lidoARM.claimRedeem(1);

        // Assertions after
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY));
        assertEq(lidoARM.balanceOf(address(this)), 0);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY);
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(DEFAULT_AMOUNT, DEFAULT_AMOUNT, 2);
        assertEqUserRequest(0, address(this), true, block.timestamp - delay, DEFAULT_AMOUNT / 2, DEFAULT_AMOUNT / 2);
        assertEqUserRequest(1, address(this), true, block.timestamp, DEFAULT_AMOUNT / 2, DEFAULT_AMOUNT);
        assertEq(assets, DEFAULT_AMOUNT / 2);
        assertEq(lidoARM.claimable(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
    }
}
