/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/EthenaARM/shared/Shared.sol";

// Contracts
import {EthenaARM} from "contracts/EthenaARM.sol";
import {EthenaUnstaker} from "contracts/EthenaUnstaker.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

contract Fork_Concrete_EthenaARM_ClaimBaseWithdrawals_Test_ is Fork_Shared_Test {
    uint256 public AMOUNT_IN = 100 ether;

    //////////////////////////////////////////////////////
    /// --- TESTS
    //////////////////////////////////////////////////////
    function test_ClaimBaseWithdrawals_FirstRequest() public {
        vm.prank(operator);
        ethenaARM.requestBaseWithdrawal(AMOUNT_IN);
        skip(7 days + 1);

        address unstakerAddress = ethenaARM.unstakers(ethenaARM.nextUnstakerIndex() - 1);
        vm.prank(operator);
        ethenaARM.claimBaseWithdrawals(unstakerAddress);
    }
}
