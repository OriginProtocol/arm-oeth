/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/EthenaARM/shared/Shared.sol";

// Contracts
import {EthenaARM} from "contracts/EthenaARM.sol";
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

        vm.expectEmit({emitter: address(ethenaARM)});
        emit EthenaARM.RequestBaseWithdrawal(
            ethenaAssetAdapter.unstakers(nextUnstakerIndex), AMOUNT_IN, susde.convertToAssets(AMOUNT_IN)
        );

        vm.prank(operator);
        ethenaARM.requestRedeem(address(susde), AMOUNT_IN);

        EthenaUnstaker unstaker = EthenaUnstaker(ethenaAssetAdapter.unstakers(nextUnstakerIndex));
        UserCooldown memory cooldown = IStakedUSDe(address(susde)).cooldowns(address(unstaker));
        uint256 susdeBalanceAfter = susde.balanceOf(address(ethenaARM));
        assertEq(susdeBalanceAfter, susdeBalanceBefore - AMOUNT_IN, "sUSDe balance after request incorrect");
        assertEq(ethenaAssetAdapter.nextUnstakerIndex(), nextUnstakerIndex + 1, "nextUnstakerIndex not incremented");
        assertEq(cooldown.underlyingAmount, susde.convertToAssets(AMOUNT_IN), "unstaker cooldown amount incorrect");
    }

    function test_RequestWithdraw_SecondRequest() public {
        // First request
        vm.prank(operator);
        ethenaARM.requestRedeem(address(susde), AMOUNT_IN);
        skip(ethenaARM.DELAY_REQUEST());

        // Second request
        uint256 susdeBalanceBefore = susde.balanceOf(address(ethenaARM));
        uint256 nextUnstakerIndex = ethenaAssetAdapter.nextUnstakerIndex();
        vm.prank(operator);
        ethenaARM.requestRedeem(address(susde), AMOUNT_IN * 2);

        UserCooldown memory cooldown =
            IStakedUSDe(address(susde)).cooldowns(ethenaAssetAdapter.unstakers(nextUnstakerIndex));
        uint256 susdeBalanceAfter = susde.balanceOf(address(ethenaARM));
        assertEq(ethenaAssetAdapter.nextUnstakerIndex(), 2, "nextUnstakerIndex not incremented");
        assertEq(susdeBalanceAfter, susdeBalanceBefore - (2 * AMOUNT_IN), "sUSDe balance after requests incorrect");
        assertEq(cooldown.underlyingAmount, susde.convertToAssets(AMOUNT_IN * 2), "second unstaker cooldown incorrect");
    }

    function test_RequestWithdraw_MaxRequest() public {
        uint256 balanceBefore = susde.balanceOf(address(ethenaARM));
        uint256 delay = ethenaARM.DELAY_REQUEST();

        // Make MAX_UNSTAKERS requests
        for (uint256 i; i < MAX_UNSTAKERS; i++) {
            vm.prank(operator);
            ethenaARM.requestRedeem(address(susde), AMOUNT_IN);
            skip(delay);
        }

        uint256 balanceAfter = susde.balanceOf(address(ethenaARM));
        assertEq(ethenaAssetAdapter.nextUnstakerIndex(), 0, "nextUnstakerIndex not wrapped around");
        assertEq(balanceBefore - balanceAfter, AMOUNT_IN * MAX_UNSTAKERS, "sUSDe balance after max requests incorrect");
    }

    //////////////////////////////////////////////////////
    /// --- REVERT TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_RequestWithdraw_RequestDelayNotPassed() public {
        vm.prank(operator);
        ethenaARM.requestRedeem(address(susde), AMOUNT_IN);

        vm.expectRevert("Adapter: delay not passed");
        vm.prank(operator);
        ethenaARM.requestRedeem(address(susde), AMOUNT_IN);
    }

    function test_RevertWhen_RequestWithdraw_InvalidUnstaker() public {
        address[42] memory emptyUnstakers;
        vm.prank(governor);
        ethenaAssetAdapter.setUnstakers(emptyUnstakers);

        vm.expectRevert("Adapter: invalid unstaker");
        vm.prank(operator);
        ethenaARM.requestRedeem(address(susde), AMOUNT_IN);
    }

    function test_RevertWhen_RequestWithdraw_UnstakerInCooldown() public {
        uint256 delay = ethenaARM.DELAY_REQUEST();

        // Make MAX_UNSTAKERS requests
        for (uint256 i; i < MAX_UNSTAKERS; i++) {
            vm.prank(operator);
            ethenaARM.requestRedeem(address(susde), AMOUNT_IN);
            skip(delay);
        }

        vm.prank(operator);
        vm.expectRevert("Adapter: unstaker in cooldown");
        ethenaARM.requestRedeem(address(susde), AMOUNT_IN);
    }

    function test_RevertWhen_RequestWithdraw_NotOperatorOrOwner() public {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        ethenaARM.requestRedeem(address(susde), AMOUNT_IN);
    }

    function test_RevertWhen_RequestWithdraw_UnauthorizedCaller() public {
        address unstakerAddress = ethenaAssetAdapter.unstakers(0);

        vm.expectRevert("Only ARM can request unstake");
        EthenaUnstaker(unstakerAddress).requestUnstake(AMOUNT_IN);
    }
}
