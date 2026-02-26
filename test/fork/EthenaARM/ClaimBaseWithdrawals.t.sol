/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/EthenaARM/shared/Shared.sol";

// Contracts
import {EthenaARM} from "contracts/EthenaARM.sol";
import {EthenaUnstaker} from "contracts/EthenaUnstaker.sol";

contract Fork_Concrete_EthenaARM_ClaimBaseWithdrawals_Test_ is Fork_Shared_Test {
    uint256 public AMOUNT_IN = 100 ether;

    //////////////////////////////////////////////////////
    /// --- TESTS
    //////////////////////////////////////////////////////
    function test_ClaimBaseWithdrawals_FirstRequest() public {
        vm.prank(operator);
        ethenaARM.requestBaseWithdrawal(AMOUNT_IN);

        uint256 amountOut = susde.convertToAssets(AMOUNT_IN);
        uint8 unstakerIndex = ethenaARM.nextUnstakerIndex() - 1;
        address unstakerAddress = ethenaARM.unstakers(unstakerIndex);
        skip(7 days + 1);

        vm.expectEmit({emitter: address(ethenaARM)});
        emit EthenaARM.ClaimBaseWithdrawals(unstakerAddress, amountOut);
        ethenaARM.claimBaseWithdrawals(unstakerIndex);
    }

    //////////////////////////////////////////////////////
    /// --- REVERT TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_ClaimBaseWithdrawals_NoCooldownAmount() public {
        vm.expectRevert("EthenaARM: No cooldown amount");
        ethenaARM.claimBaseWithdrawals(0);
    }

    function test_RevertWhen_ClaimBaseWithdrawals_InvalidUnstakerIndex() public {
        address[42] memory emptyUnstakers;
        vm.prank(ethenaARM.owner());
        ethenaARM.setUnstakers(emptyUnstakers);

        vm.expectRevert("EthenaARM: Invalid unstaker");
        ethenaARM.claimBaseWithdrawals(0);
    }

    function test_RevertWhen_ClaimBaseWithdrawals_InvalidUnstaker() public {
        vm.prank(operator);
        ethenaARM.requestBaseWithdrawal(AMOUNT_IN);
        address unstaker = ethenaARM.unstakers(0);
        skip(7 days + 1);
        vm.expectRevert("Only ARM can request unstake");
        EthenaUnstaker(unstaker).claimUnstake();
    }
}
