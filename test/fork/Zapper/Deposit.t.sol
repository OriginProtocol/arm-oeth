// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {CapManager} from "src/contracts/CapManager.sol";
import {ZapperLidoARM} from "contracts/ZapperLidoARM.sol";

contract Fork_Concrete_ZapperLidoARM_Deposit_Test_ is Fork_Shared_Test_ {
    function setUp() public override {
        super.setUp();

        vm.deal(address(this), DEFAULT_AMOUNT);
    }

    function test_Deposit_ViaFunction() public {
        assertEq(lidoARM.balanceOf(address(this)), 0);
        uint256 expectedShares = lidoARM.previewDeposit(DEFAULT_AMOUNT);
        uint256 capBefore = capManager.liquidityProviderCaps(address(this));

        vm.expectEmit({emitter: address(capManager)});
        emit CapManager.LiquidityProviderCap(address(this), capBefore - DEFAULT_AMOUNT);
        vm.expectEmit({emitter: address(zapperLidoARM)});
        emit ZapperLidoARM.Zap(address(this), DEFAULT_AMOUNT, expectedShares);
        // Deposit
        zapperLidoARM.deposit{value: DEFAULT_AMOUNT}();

        // Check balance
        assertEq(lidoARM.balanceOf(address(this)), DEFAULT_AMOUNT);
        assertEq(capManager.liquidityProviderCaps(address(this)), capBefore - DEFAULT_AMOUNT);
    }

    function test_Deposit_ViaCall() public {
        assertEq(lidoARM.balanceOf(address(this)), 0);
        uint256 expectedShares = lidoARM.previewDeposit(DEFAULT_AMOUNT);
        uint256 capBefore = capManager.liquidityProviderCaps(address(this));

        vm.expectEmit({emitter: address(capManager)});
        emit CapManager.LiquidityProviderCap(address(this), capBefore - DEFAULT_AMOUNT);
        vm.expectEmit({emitter: address(zapperLidoARM)});
        emit ZapperLidoARM.Zap(address(this), DEFAULT_AMOUNT, expectedShares);
        // Deposit
        (bool success,) = address(zapperLidoARM).call{value: DEFAULT_AMOUNT}("");
        assertTrue(success);

        // Check balance
        assertEq(lidoARM.balanceOf(address(this)), DEFAULT_AMOUNT);
        assertEq(capManager.liquidityProviderCaps(address(this)), capBefore - DEFAULT_AMOUNT);
    }
}
