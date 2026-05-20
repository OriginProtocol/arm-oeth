// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_LidoARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";
import {Ownable} from "contracts/Ownable.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";

/// @notice Coverage for `pause()` (operator or owner) and `unpause()` (owner only).
///         The downstream `whenNotPaused` reverts on user-facing functions are
///         already covered in the per-function test files (Deposit, ClaimRedeem,
///         RequestRedeem, Swap*). Here we focus on the access control, the
///         `paused` state flip, and the events.
contract Unit_LidoARM_Pause_Test is Unit_LidoARM_Shared_Test {
    //////////////////////////////////////////////////////
    /// --- pause
    //////////////////////////////////////////////////////
    function test_Pause_ByOwner() public {
        assertEq(lidoARM.paused(), false, "paused pre");

        vm.expectEmit(address(lidoARM));
        emit AbstractARM.Paused(governor);

        vm.prank(governor);
        lidoARM.pause();

        assertEq(lidoARM.paused(), true, "paused post");
    }

    function test_Pause_ByOperator() public {
        assertEq(lidoARM.paused(), false, "paused pre");

        vm.expectEmit(address(lidoARM));
        emit AbstractARM.Paused(operator);

        vm.prank(operator);
        lidoARM.pause();

        assertEq(lidoARM.paused(), true, "paused post");
    }

    function test_Pause_RevertWhen_NotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        lidoARM.pause();
    }

    //////////////////////////////////////////////////////
    /// --- unpause
    //////////////////////////////////////////////////////
    function test_Unpause_ByOwner() public {
        vm.prank(governor);
        lidoARM.pause();
        assertEq(lidoARM.paused(), true, "paused pre");

        vm.expectEmit(address(lidoARM));
        emit AbstractARM.Unpaused(governor);

        vm.prank(governor);
        lidoARM.unpause();

        assertEq(lidoARM.paused(), false, "paused post");
    }

    function test_Unpause_RevertWhen_Operator() public {
        // The operator can pause but cannot unpause — that's reserved for the owner.
        vm.prank(operator);
        lidoARM.pause();

        vm.prank(operator);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        lidoARM.unpause();
    }

    function test_Unpause_RevertWhen_NotAuthorized() public {
        vm.prank(governor);
        lidoARM.pause();

        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        lidoARM.unpause();
    }
}
