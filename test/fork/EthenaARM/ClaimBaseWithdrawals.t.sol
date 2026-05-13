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
        ethenaARM.requestRedeem(address(susde), AMOUNT_IN);

        uint256 amountOut = susde.convertToAssets(AMOUNT_IN);
        uint8 unstakerIndex = ethenaAssetAdapter.nextUnstakerIndex() - 1;
        address unstakerAddress = ethenaAssetAdapter.unstakers(unstakerIndex);
        skip(7 days + 1);

        vm.expectEmit({emitter: address(ethenaARM)});
        emit EthenaARM.ClaimBaseWithdrawals(unstakerAddress, amountOut);
        ethenaARM.claimRedeem(address(susde), ethenaAssetAdapter.requestShares(unstakerAddress));
    }

    //////////////////////////////////////////////////////
    /// --- REVERT TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_ClaimBaseWithdrawals_NoCooldownAmount() public {
        vm.expectRevert("EthenaARM: No cooldown amount");
        ethenaARM.claimRedeem(address(susde), AMOUNT_IN);
    }

    function test_RevertWhen_ClaimBaseWithdrawals_InvalidUnstakerIndex() public {
        address[42] memory emptyUnstakers;
        vm.prank(ethenaARM.owner());
        ethenaAssetAdapter.setUnstakers(emptyUnstakers);

        vm.expectRevert("Adapter: redeem exceeds claimable");
        ethenaARM.claimRedeem(address(susde), AMOUNT_IN);
    }

    function test_RevertWhen_ClaimBaseWithdrawals_InvalidUnstaker() public {
        vm.prank(operator);
        ethenaARM.requestRedeem(address(susde), AMOUNT_IN);
        address unstaker = ethenaAssetAdapter.unstakers(0);
        skip(7 days + 1);
        vm.expectRevert("Only ARM can request unstake");
        EthenaUnstaker(unstaker).claimUnstake();
    }
}
