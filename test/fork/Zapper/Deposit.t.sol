// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {ZapperLidoARM} from "contracts/ZapperLidoARM.sol";

contract Fork_Concrete_ZapperLidoARM_Deposit_Test_ is Fork_Shared_Test_ {
    function setUp() public override {
        super.setUp();

        vm.deal(address(this), DEFAULT_AMOUNT);
    }

    function test_Deposit_ViaFunction() public setLiquidityProviderCap(address(zapperLidoARM), DEFAULT_AMOUNT) {
        assertEq(lidoARM.balanceOf(address(this)), 0);
        uint256 expectedShares = lidoARM.previewDeposit(DEFAULT_AMOUNT);

        vm.expectEmit({emitter: address(zapperLidoARM)});
        emit ZapperLidoARM.Zap(address(this), DEFAULT_AMOUNT, expectedShares);
        // Deposit
        zapperLidoARM.deposit{value: DEFAULT_AMOUNT}();

        // Check balance
        assertEq(lidoARM.balanceOf(address(this)), DEFAULT_AMOUNT);
    }

    function test_Deposit_ViaCall() public setLiquidityProviderCap(address(zapperLidoARM), DEFAULT_AMOUNT) {
        assertEq(lidoARM.balanceOf(address(this)), 0);
        uint256 expectedShares = lidoARM.previewDeposit(DEFAULT_AMOUNT);

        vm.expectEmit({emitter: address(zapperLidoARM)});
        emit ZapperLidoARM.Zap(address(this), DEFAULT_AMOUNT, expectedShares);
        // Deposit
        (bool success,) = address(zapperLidoARM).call{value: DEFAULT_AMOUNT}("");
        assertTrue(success);

        // Check balance
        assertEq(lidoARM.balanceOf(address(this)), DEFAULT_AMOUNT);
    }
}
