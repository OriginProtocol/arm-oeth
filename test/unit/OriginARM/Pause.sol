// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {Ownable} from "contracts/Ownable.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";

contract Unit_Concrete_OriginARM_Pause_Test_ is Unit_Shared_Test {
    function setUp() public virtual override {
        super.setUp();

        // Give Alice some WETH and approval so she can interact with the ARM in every test
        deal(address(weth), alice, 1_000 * DEFAULT_AMOUNT);
        vm.prank(alice);
        weth.approve(address(originARM), type(uint256).max);
    }

    ////////////////////////////////////////////////////
    /// --- pause()
    ////////////////////////////////////////////////////
    function test_RevertWhen_Pause_Because_NotOperatorNorGovernor() public asNotOperatorNorGovernor {
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        originARM.pause();
    }

    function test_Pause_AsOperator() public {
        assertEq(originARM.paused(), false, "ARM should not be paused before");

        vm.expectEmit(address(originARM));
        emit AbstractARM.Paused(operator);

        vm.prank(operator);
        originARM.pause();

        assertEq(originARM.paused(), true, "ARM should be paused after");
    }

    function test_Pause_AsGovernor() public {
        assertEq(originARM.paused(), false, "ARM should not be paused before");

        vm.expectEmit(address(originARM));
        emit AbstractARM.Paused(governor);

        vm.prank(governor);
        originARM.pause();

        assertEq(originARM.paused(), true, "ARM should be paused after");
    }

    /// @notice Pausing an already-paused ARM is a no-op state-wise but still emits the event.
    function test_Pause_WhenAlreadyPaused() public {
        vm.prank(governor);
        originARM.pause();
        assertEq(originARM.paused(), true, "ARM should be paused");

        vm.expectEmit(address(originARM));
        emit AbstractARM.Paused(operator);

        vm.prank(operator);
        originARM.pause();

        assertEq(originARM.paused(), true, "ARM should still be paused");
    }

    ////////////////////////////////////////////////////
    /// --- unpause()
    ////////////////////////////////////////////////////
    function test_RevertWhen_Unpause_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert(Ownable.OnlyOwner.selector);
        originARM.unpause();
    }

    function test_RevertWhen_Unpause_Because_OperatorCannotUnpause() public asOperator {
        vm.expectRevert(Ownable.OnlyOwner.selector);
        originARM.unpause();
    }

    function test_Unpause_AsGovernor() public {
        // First pause the ARM
        vm.prank(governor);
        originARM.pause();
        assertEq(originARM.paused(), true, "ARM should be paused before");

        vm.expectEmit(address(originARM));
        emit AbstractARM.Unpaused(governor);

        vm.prank(governor);
        originARM.unpause();

        assertEq(originARM.paused(), false, "ARM should not be paused after");
    }

    ////////////////////////////////////////////////////
    /// --- whenNotPaused: deposit() / requestRedeem()
    ////////////////////////////////////////////////////
    function test_RevertWhen_Deposit_Because_Paused() public {
        vm.prank(operator);
        originARM.pause();

        vm.expectRevert(AbstractARM.ContractPaused.selector);
        vm.prank(alice);
        originARM.deposit(DEFAULT_AMOUNT);
    }

    function test_RevertWhen_DepositWithReceiver_Because_Paused() public {
        vm.prank(operator);
        originARM.pause();

        vm.expectRevert(AbstractARM.ContractPaused.selector);
        vm.prank(alice);
        originARM.deposit(DEFAULT_AMOUNT, bob);
    }

    function test_RevertWhen_RequestRedeem_Because_Paused() public {
        // First deposit so alice has shares to redeem
        vm.prank(alice);
        originARM.deposit(DEFAULT_AMOUNT);

        vm.prank(operator);
        originARM.pause();

        vm.expectRevert(AbstractARM.ContractPaused.selector);
        vm.prank(alice);
        originARM.requestRedeem(DEFAULT_AMOUNT);
    }

    /// @notice After unpause, deposit and requestRedeem work again.
    function test_DepositAndRedeem_After_Unpause() public {
        // Pause then unpause
        vm.prank(operator);
        originARM.pause();
        vm.prank(governor);
        originARM.unpause();

        // Deposit
        vm.prank(alice);
        uint256 shares = originARM.deposit(DEFAULT_AMOUNT);
        assertGt(shares, 0, "Alice should have received shares");

        // Request redeem
        vm.prank(alice);
        (uint256 requestId,) = originARM.requestRedeem(shares);
        assertEq(requestId, 0, "First request");
    }

    function test_RevertWhen_ClaimRedeem_Because_Paused() public {
        // Alice deposits then requests a full redeem
        vm.startPrank(alice);
        uint256 shares = originARM.deposit(DEFAULT_AMOUNT);
        originARM.requestRedeem(shares);
        vm.stopPrank();

        // Pause the ARM
        vm.prank(operator);
        originARM.pause();

        // Wait for the claim delay
        vm.warp(block.timestamp + CLAIM_DELAY);

        uint256 balanceBefore = weth.balanceOf(alice);
        vm.expectRevert(AbstractARM.ContractPaused.selector);
        vm.prank(alice);
        originARM.claimRedeem(0);
        assertEq(weth.balanceOf(alice), balanceBefore, "Alice should not claim while paused");
    }
}
