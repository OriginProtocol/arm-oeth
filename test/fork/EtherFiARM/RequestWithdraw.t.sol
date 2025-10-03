/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/EtherFiARM/shared/Shared.sol";

contract Fork_Concrete_EtherFiARM_RequestWithdraw_Test_ is Fork_Shared_Test {
    function test() public {
        // Fund the ARM with eETH from weETH
        vm.prank(address(weeth));
        eeth.transfer(address(etherfiARM), 10 ether);

        // Request a withdrawal
        vm.prank(operator);
        uint256 requestId = etherfiARM.requestEtherFiWithdrawal(1 ether);

        // Process finalization on withdrawal queue
        // We cheat a bit here, because we don't follow the full finalization process it could fail
        // if there is not enough liquidity, but since the amount to claim is low, it should be fine
        vm.prank(0x0EF8fa4760Db8f5Cd4d993f3e3416f30f942D705);
        etherfiWithdrawalNFT.finalizeRequests(requestId);

        // Claim the withdrawal
        uint256[] memory requestIdArray = new uint256[](1);
        requestIdArray[0] = requestId;
        vm.prank(operator);
        etherfiARM.claimEtherFiWithdrawals(requestIdArray);
    }
}
