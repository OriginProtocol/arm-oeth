// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

contract Fork_Concrete_LidoARM_CollectFees_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    /// @notice This test is expected to revert as almost all the liquidity is in stETH
    function test_RevertWhen_CollectFees_Because_InsufficientLiquidity()
        public
        simulateAssetGainInLidoARM(DEFAULT_AMOUNT, address(steth), true)
    {
        vm.expectRevert("ARM: insufficient liquidity");
        lidoARM.collectFees();
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_CollectFees_Once() public simulateAssetGainInLidoARM(DEFAULT_AMOUNT, address(weth), true) {
        address feeCollector = lidoARM.feeCollector();
        uint256 fee = DEFAULT_AMOUNT * 20 / 100;

        // Expected Events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), feeCollector, fee);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.FeeCollected(feeCollector, fee);

        // Main call
        uint256 claimedFee = lidoARM.collectFees();

        // Assertions after
        assertEq(claimedFee, fee);
        assertEq(lidoARM.feesAccrued(), 0);
    }

    function test_CollectFees_Twice()
        public
        simulateAssetGainInLidoARM(DEFAULT_AMOUNT, address(weth), true)
        collectFeesOnLidoARM
        simulateAssetGainInLidoARM(DEFAULT_AMOUNT, address(weth), true)
    {
        // Main call
        uint256 claimedFee = lidoARM.collectFees();

        // Assertions after
        assertEq(claimedFee, DEFAULT_AMOUNT * 20 / 100); // This test should pass!
    }
}
