/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/EthenaARM/shared/Shared.sol";

import {IStakedUSDe, UserCooldown} from "contracts/Interfaces.sol";
import {EthenaUnstaker} from "contracts/EthenaUnstaker.sol";

contract Fork_Concrete_EthenaARM_RequestWithdraw_Test_ is Fork_Shared_Test {
    uint256 public AMOUNT_IN = 100 ether;

    //////////////////////////////////////////////////////
    /// --- TESTS
    //////////////////////////////////////////////////////
    function test_RequestWithdraw_FirstRequest() public {
        uint256 susdeBalanceBefore = susde.balanceOf(address(ethenaARM));
        uint256 nextUnstakerIndex = ethenaAssetAdapter.nextUnstakerIndex();
        uint256 expectedAssets = susde.convertToAssets(AMOUNT_IN);

        vm.prank(operator);
        (uint256 sharesRequested, uint256 assetsExpected) = ethenaARM.requestBaseAssetRedeem(address(susde), AMOUNT_IN);

        EthenaUnstaker unstaker = EthenaUnstaker(ethenaAssetAdapter.unstakers(nextUnstakerIndex));
        UserCooldown memory cooldown = IStakedUSDe(address(susde)).cooldowns(address(unstaker));
        uint256 susdeBalanceAfter = susde.balanceOf(address(ethenaARM));
        assertEq(sharesRequested, AMOUNT_IN, "shares requested incorrect");
        assertEq(assetsExpected, expectedAssets, "assets expected incorrect");
        assertEq(susdeBalanceAfter, susdeBalanceBefore - AMOUNT_IN, "sUSDe balance after request incorrect");
        assertEq(ethenaAssetAdapter.nextUnstakerIndex(), nextUnstakerIndex + 1, "nextUnstakerIndex not incremented");
        assertEq(cooldown.underlyingAmount, expectedAssets, "unstaker cooldown amount incorrect");
    }

    function test_RequestWithdraw_SecondRequest() public {
        // First request
        vm.prank(operator);
        ethenaARM.requestBaseAssetRedeem(address(susde), AMOUNT_IN);
        skip(DELAY_REQUEST);

        // Second request
        uint256 susdeBalanceBefore = susde.balanceOf(address(ethenaARM));
        uint256 nextUnstakerIndex = ethenaAssetAdapter.nextUnstakerIndex();
        vm.prank(operator);
        ethenaARM.requestBaseAssetRedeem(address(susde), AMOUNT_IN * 2);

        UserCooldown memory cooldown =
            IStakedUSDe(address(susde)).cooldowns(ethenaAssetAdapter.unstakers(nextUnstakerIndex));
        uint256 susdeBalanceAfter = susde.balanceOf(address(ethenaARM));
        assertEq(ethenaAssetAdapter.nextUnstakerIndex(), 2, "nextUnstakerIndex not incremented");
        assertEq(susdeBalanceAfter, susdeBalanceBefore - (2 * AMOUNT_IN), "sUSDe balance after requests incorrect");
        assertEq(cooldown.underlyingAmount, susde.convertToAssets(AMOUNT_IN * 2), "second unstaker cooldown incorrect");
    }

    function test_RequestWithdraw_MaxRequest() public {
        uint256 balanceBefore = susde.balanceOf(address(ethenaARM));
        uint256 delay = DELAY_REQUEST;

        // Make MAX_UNSTAKERS requests
        for (uint256 i; i < MAX_UNSTAKERS; i++) {
            vm.prank(operator);
            ethenaARM.requestBaseAssetRedeem(address(susde), AMOUNT_IN);
            skip(delay);
        }

        uint256 balanceAfter = susde.balanceOf(address(ethenaARM));
        assertEq(ethenaAssetAdapter.nextUnstakerIndex(), 0, "nextUnstakerIndex not wrapped around");
        assertEq(balanceBefore - balanceAfter, AMOUNT_IN * MAX_UNSTAKERS, "sUSDe balance after max requests incorrect");
    }

    function test_SetUnstakers_ReplacesIdleUnstakers() public {
        address[42] memory replacementUnstakers = _deployUnstakers();

        vm.prank(governor);
        ethenaAssetAdapter.setUnstakers(replacementUnstakers);

        assertEq(ethenaAssetAdapter.unstakers(0), replacementUnstakers[0], "unstaker not replaced");
    }

    function test_SetUnstakers_AllowsSameArrayWithPendingRequest() public {
        vm.prank(operator);
        ethenaARM.requestBaseAssetRedeem(address(susde), AMOUNT_IN);

        address[42] memory currentUnstakers = _currentUnstakers();

        vm.prank(governor);
        ethenaAssetAdapter.setUnstakers(currentUnstakers);

        assertEq(ethenaAssetAdapter.unstakers(0), currentUnstakers[0], "unstaker changed");
    }

    //////////////////////////////////////////////////////
    /// --- REVERT TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_RequestWithdraw_RequestDelayNotPassed() public {
        vm.prank(operator);
        ethenaARM.requestBaseAssetRedeem(address(susde), AMOUNT_IN);

        vm.expectRevert("Adapter: delay not passed");
        vm.prank(operator);
        ethenaARM.requestBaseAssetRedeem(address(susde), AMOUNT_IN);
    }

    function test_RevertWhen_RequestWithdraw_InvalidUnstaker() public {
        address[42] memory emptyUnstakers;
        vm.prank(governor);
        ethenaAssetAdapter.setUnstakers(emptyUnstakers);

        vm.expectRevert("Adapter: invalid unstaker");
        vm.prank(operator);
        ethenaARM.requestBaseAssetRedeem(address(susde), AMOUNT_IN);
    }

    function test_RevertWhen_SetUnstakers_ReplacesPendingUnstaker() public {
        vm.prank(operator);
        ethenaARM.requestBaseAssetRedeem(address(susde), AMOUNT_IN);

        address[42] memory replacementUnstakers = _currentUnstakers();
        replacementUnstakers[0] = address(new EthenaUnstaker(address(ethenaAssetAdapter), IStakedUSDe(address(susde))));

        vm.expectRevert("Adapter: unstaker pending");
        vm.prank(governor);
        ethenaAssetAdapter.setUnstakers(replacementUnstakers);
    }

    function test_RevertWhen_RequestWithdraw_UnstakerInCooldown() public {
        uint256 delay = DELAY_REQUEST;

        // Make MAX_UNSTAKERS requests
        for (uint256 i; i < MAX_UNSTAKERS; i++) {
            vm.prank(operator);
            ethenaARM.requestBaseAssetRedeem(address(susde), AMOUNT_IN);
            skip(delay);
        }

        vm.prank(operator);
        vm.expectRevert("Adapter: unstaker in cooldown");
        ethenaARM.requestBaseAssetRedeem(address(susde), AMOUNT_IN);
    }

    function test_RevertWhen_RequestWithdraw_NotOperatorOrOwner() public {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        ethenaARM.requestBaseAssetRedeem(address(susde), AMOUNT_IN);
    }

    function test_RevertWhen_RequestWithdraw_UnauthorizedCaller() public {
        address unstakerAddress = ethenaAssetAdapter.unstakers(0);

        vm.expectRevert("Only ARM can request unstake");
        EthenaUnstaker(unstakerAddress).requestUnstake(AMOUNT_IN);
    }

    function _currentUnstakers() internal view returns (address[42] memory currentUnstakers) {
        for (uint256 i; i < MAX_UNSTAKERS; ++i) {
            currentUnstakers[i] = ethenaAssetAdapter.unstakers(i);
        }
    }
}
