// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

contract Unit_Concrete_OriginARM_Setters_Test_ is Unit_Shared_Test {
    ////////////////////////////////////////////////////
    /// --- REVERT
    ////////////////////////////////////////////////////
    function test_RevertWhen_SetFeeCollector_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert("ARM: Only owner can call this function.");
        originARM.setFeeCollector(address(0));
    }

    function test_RevertWhen_SetFeeCollector_Because_FeeCollectorIsZero() public asGovernor {
        vm.expectRevert("ARM: invalid fee collector");
        originARM.setFeeCollector(address(0));
    }

    function test_RevertWhen_SetFee_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert("ARM: Only owner can call this function.");
        originARM.setFee(0);
    }

    function test_RevertWhen_SetFee_Because_FeeIsTooHigh() public asGovernor {
        uint256 FEE_SCALE = originARM.FEE_SCALE();
        vm.expectRevert("ARM: fee too high");
        originARM.setFee(FEE_SCALE / 2 + 1);
    }

    ////////////////////////////////////////////////////
    /// --- TESTS
    ////////////////////////////////////////////////////
    function test_SetFeeCollector() public asGovernor {
        address newCollector = vm.randomAddress();
        assertNotEq(originARM.feeCollector(), newCollector, "Wrong fee collector");

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.FeeCollectorUpdated(newCollector);

        originARM.setFeeCollector(newCollector);
        assertEq(originARM.feeCollector(), newCollector, "Wrong fee collector");
    }

    function test_SetFee_When_NothingToClaim() public asGovernor {
        // In this situation there is nothing to claim as we are right after deployment
        // and no swap has been done yet, so no fee has to be collected.
        uint256 newFee = originARM.fee() + 1;
        assertNotEq(originARM.fee(), newFee, "Wrong fee");
        uint256 feeCollectorBalanceBefore = weth.balanceOf(originARM.feeCollector());

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.FeeUpdated(newFee);

        originARM.setFee(newFee);
        assertEq(originARM.fee(), newFee, "Wrong fee");
        assertEq(weth.balanceOf(originARM.feeCollector()), feeCollectorBalanceBefore, "Wrong fee collector balance");
    }

    function test_SetFee_When_SomethingToClaim() public swapAllWETHForOETH swapAllOETHForWETH asGovernor {
        // Swap one way and then the other way to have some fees to claim and liquidity to claim it.
        uint256 newFee = originARM.fee() + 1;
        assertNotEq(originARM.fee(), newFee, "Wrong fee");
        uint256 feeToCollect = originARM.feesAccrued();
        address feeCollector = originARM.feeCollector();
        uint256 feeCollectorBalanceBefore = weth.balanceOf(feeCollector);

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.FeeCollected(feeCollector, feeToCollect);
        vm.expectEmit(address(originARM));
        emit AbstractARM.FeeUpdated(newFee);

        originARM.setFee(newFee);
        assertEq(originARM.fee(), newFee, "Wrong fee");
        assertEq(weth.balanceOf(feeCollector), feeCollectorBalanceBefore + feeToCollect, "Wrong fee collector balance");
    }
}
