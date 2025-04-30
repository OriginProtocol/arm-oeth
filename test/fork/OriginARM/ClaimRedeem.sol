// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AbstractARM} from "contracts/AbstractARM.sol";
import {Fork_Shared_Test} from "test/fork/OriginARM/shared/Shared.sol";

contract Fork_Concrete_OriginARM_ClaimRedeem_Test_ is Fork_Shared_Test {
    function test_ClaimRedeem_When_EnoughLiquidityInARM()
        public
        setFee(0)
        deposit(alice, DEFAULT_AMOUNT)
        requestRedeemAll(alice)
        timejump(CLAIM_DELAY)
    {
        // Assertions before claim
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "totalAssets before");
        assertEq(ws.balanceOf(address(alice)), 0, "ws balance before");

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.RedeemClaimed(address(alice), 0, DEFAULT_AMOUNT);

        // Main call
        vm.prank(alice);
        originARM.claimRedeem(0);

        // Assertions after claim
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "totalAssets after");
        assertEq(ws.balanceOf(address(alice)), DEFAULT_AMOUNT, "ws balance after");
    }

    function test_ClaimRedeem_WhenNotEnoughLiquidityInARM_ButEnoughInMarket()
        public
        setFee(0)
        setARMBuffer(0)
        deposit(alice, DEFAULT_AMOUNT)
        addMarket(address(siloMarket))
        setActiveMarket(address(siloMarket))
        requestRedeemAll(alice)
    {
        // Assertions before claim
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "totalAssets before");
        assertEq(ws.balanceOf(address(alice)), 0, "ws balance before");

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.RedeemClaimed(address(alice), 0, DEFAULT_AMOUNT - 1);

        // Main call
        skip(CLAIM_DELAY);
        vm.prank(alice);
        originARM.claimRedeem(0);

        // Assertions after claim
        assertGt(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "totalAssets after");
        assertApproxEqAbs(ws.balanceOf(address(alice)), DEFAULT_AMOUNT, 1, "ws balance after");
    }
}
