// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_LidoARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

contract Unit_LidoARM_Deposit_Test is Unit_LidoARM_Shared_Test {
    function setUp() public override {
        super.setUp();
        desactiveCapManager();

        // Give Alice some ETH to work with
        deal(address(weth), alice, 100 ether);
    }

    //////////////////////////////////////////////////////
    /// ---              Happy paths                   ---
    //////////////////////////////////////////////////////
    function test_Deposit_Default() public {
        // Given
        uint256 amount = 1 ether;
        uint256 expectedShares = amount; // 1:1 for simplicity
        assertEq(lidoARM.convertToShares(amount), expectedShares, "Unexpected share conversion");
        assertEq(lidoARM.totalAssets(), 1e12, "Unexpected total assets before deposit");
        assertEq(lidoARM.totalSupply(), 1e12, "Unexpected total shares before deposit");

        // Expect
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(lidoARM), amount);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), alice, expectedShares);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.Deposit(alice, amount, expectedShares);

        // When
        vm.prank(alice);
        lidoARM.deposit(amount);

        // Then
        assertEq(weth.balanceOf(alice), 99 ether, "Unexpected WETH balance for Alice after deposit");
        assertEq(lidoARM.balanceOf(alice), expectedShares, "Unexpected LidoARM share balance for Alice after deposit");
        assertEq(lidoARM.totalAssets(), 1e12 + amount, "Unexpected total assets after deposit");
        assertEq(lidoARM.totalSupply(), 1e12 + expectedShares, "Unexpected total shares after deposit");
    }

    function test_Deposit_SecondDeposit() public {
        // Given
        uint256 firstAmount = 1 ether;
        uint256 secondAmount = 3 ether;
        uint256 expectedFirstShares = firstAmount; // 1:1 for simplicity
        uint256 expectedSecondShares = secondAmount; // 1:1 for simplicity

        // Give Bobby some WETH for the second deposit
        deal(address(weth), bobby, 100 ether);

        // First deposit by Alice
        vm.prank(alice);
        lidoARM.deposit(firstAmount);

        // Sanity check state after first deposit
        assertEq(lidoARM.balanceOf(alice), expectedFirstShares, "Unexpected Alice shares after first deposit");
        assertEq(lidoARM.totalAssets(), 1e12 + firstAmount, "Unexpected total assets after first deposit");
        assertEq(lidoARM.totalSupply(), 1e12 + expectedFirstShares, "Unexpected total shares after first deposit");

        // Expect events for second deposit (by Bobby)
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(bobby, address(lidoARM), secondAmount);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), bobby, expectedSecondShares);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.Deposit(bobby, secondAmount, expectedSecondShares);

        // When: second deposit by Bobby
        vm.prank(bobby);
        lidoARM.deposit(secondAmount);

        // Then
        assertEq(weth.balanceOf(alice), 99 ether, "Unexpected WETH balance for Alice after second deposit");
        assertEq(weth.balanceOf(bobby), 97 ether, "Unexpected WETH balance for Bobby after second deposit");
        assertEq(lidoARM.balanceOf(alice), expectedFirstShares, "Unexpected Alice shares after second deposit");
        assertEq(lidoARM.balanceOf(bobby), expectedSecondShares, "Unexpected Bobby shares after second deposit");
        assertEq(
            lidoARM.totalAssets(), 1e12 + firstAmount + secondAmount, "Unexpected total assets after second deposit"
        );
        assertEq(
            lidoARM.totalSupply(),
            1e12 + expectedFirstShares + expectedSecondShares,
            "Unexpected total shares after second deposit"
        );
    }

    function test_Deposit_Default_With_Cap() public {
        // Given
        uint256 amount = 1 ether;
        uint256 expectedShares = amount; // 1:1 for simplicity
        assertEq(lidoARM.convertToShares(amount), expectedShares, "Unexpected share conversion");
        assertEq(lidoARM.totalAssets(), 1e12, "Unexpected total assets before deposit");
        assertEq(lidoARM.totalSupply(), 1e12, "Unexpected total shares before deposit");

        // Set a cap that allows the deposit
        address[] memory lps = new address[](1);
        lps[0] = alice;
        vm.startPrank(governor);
        capManager.setLiquidityProviderCaps(lps, 10 ether);
        capManager.setTotalAssetsCap(10 ether);
        lidoARM.setCapManager(address(capManager));
        vm.stopPrank();

        // Expect
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(lidoARM), amount);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), alice, expectedShares);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.Deposit(alice, amount, expectedShares);

        // When
        vm.prank(alice);
        lidoARM.deposit(amount);

        // Then
        assertEq(weth.balanceOf(alice), 99 ether, "Unexpected WETH balance for Alice after deposit");
        assertEq(lidoARM.balanceOf(alice), expectedShares, "Unexpected LidoARM share balance for Alice after deposit");
        assertEq(lidoARM.totalAssets(), 1e12 + amount, "Unexpected total assets after deposit");
        assertEq(lidoARM.totalSupply(), 1e12 + expectedShares, "Unexpected total shares after deposit");
    }

    //////////////////////////////////////////////////////
    /// ---                  REVERTS                   ---
    //////////////////////////////////////////////////////
    function test_Deposit_RevertWhen_Insolvent() public {
        // Alice deposit 100 ether to be solvent
        aliceFirstDeposit();

        // Alice withdraw some share to prevent `reservedWithdrawLiquidity == 0`.
        vm.prank(alice);
        lidoARM.requestRedeem(50 ether);

        // Simulate a loss by reducing the total assets (e.g., due to a failed strategy or slashing)
        uint256 balance = weth.balanceOf(address(lidoARM));
        vm.prank(address(lidoARM));
        weth.transfer(address(0), balance - 10 wei); // Leave a tiny amount to avoid zero total assets

        // Expect revert due to insolvency
        vm.prank(alice);
        vm.expectRevert("ARM: insolvent");
        lidoARM.deposit(1 ether);
    }
}
