// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {MultiLP} from "contracts/MultiLP.sol";
import {PerformanceFee} from "contracts/PerformanceFee.sol";

contract Fork_Concrete_LidoFixedPriceMultiLpARM_Setters_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
    }

    //////////////////////////////////////////////////////
    /// --- PERFORMANCE FEE - REVERTING TEST
    //////////////////////////////////////////////////////
    function test_RevertWhen_PerformanceFee_SetFee_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoFixedPriceMulltiLpARM.setFee(0);
    }

    function test_RevertWhen_PerformanceFee_SetFee_Because_FeeIsTooHigh() public asLidoFixedPriceMultiLpARMOwner {
        uint256 max = lidoFixedPriceMulltiLpARM.FEE_SCALE();
        vm.expectRevert("ARM: fee too high");
        lidoFixedPriceMulltiLpARM.setFee(max + 1);
    }

    function test_RevertWhen_PerformanceFee_SetFeeCollector_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoFixedPriceMulltiLpARM.setFeeCollector(address(0));
    }

    function test_RevertWhen_PerformanceFee_SetFeeCollector_Because_FeeCollectorIsZero() public asLidoFixedPriceMultiLpARMOwner {
        vm.expectRevert("ARM: invalid fee collector");
        lidoFixedPriceMulltiLpARM.setFeeCollector(address(0));
    }

    //////////////////////////////////////////////////////
    /// --- PERFORMANCE FEE - PASSING TEST
    //////////////////////////////////////////////////////
    function test_PerformanceFee_SetFee_() public asLidoFixedPriceMultiLpARMOwner {
        uint256 feeBefore = lidoFixedPriceMulltiLpARM.fee();

        uint256 newFee = _bound(vm.randomUint(), 0, lidoFixedPriceMulltiLpARM.FEE_SCALE());

        vm.expectEmit({emitter: address(lidoFixedPriceMulltiLpARM)});
        emit PerformanceFee.FeeUpdated(newFee);
        lidoFixedPriceMulltiLpARM.setFee(newFee);

        assertEq(lidoFixedPriceMulltiLpARM.fee(), newFee);
        assertNotEq(feeBefore, lidoFixedPriceMulltiLpARM.fee());
    }

    function test_PerformanceFee_SetFeeCollector() public asLidoFixedPriceMultiLpARMOwner {
        address feeCollectorBefore = lidoFixedPriceMulltiLpARM.feeCollector();

        address newFeeCollector = vm.randomAddress();

        vm.expectEmit({emitter: address(lidoFixedPriceMulltiLpARM)});
        emit PerformanceFee.FeeCollectorUpdated(newFeeCollector);
        lidoFixedPriceMulltiLpARM.setFeeCollector(newFeeCollector);

        assertEq(lidoFixedPriceMulltiLpARM.feeCollector(), newFeeCollector);
        assertNotEq(feeCollectorBefore, lidoFixedPriceMulltiLpARM.feeCollector());
    }
}
