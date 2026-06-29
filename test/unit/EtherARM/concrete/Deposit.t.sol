// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_EtherARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Unit_EtherARM_Deposit_Test is Unit_EtherARM_Shared_Test {
    using Math for uint256;

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
        assertEq(etherARM.convertToShares(amount), expectedShares, "convertToShares");
        assertEq(etherARM.totalAssets(), 1e12, "totalAssets pre");
        assertEq(etherARM.totalSupply(), 1e12, "totalSupply pre");
        assertEq(etherARM.previewDeposit(amount), expectedShares, "previewDeposit");

        // Expect
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(etherARM), amount);
        vm.expectEmit({emitter: address(etherARM)});
        emit IERC20.Transfer(address(0), alice, expectedShares);
        vm.expectEmit({emitter: address(etherARM)});
        emit AbstractARM.Deposit(alice, amount, expectedShares);

        // When
        vm.prank(alice);
        etherARM.deposit(amount);

        // Then
        assertEq(weth.balanceOf(alice), 99 ether, "alice weth");
        assertEq(etherARM.balanceOf(alice), expectedShares, "alice shares");
        assertEq(etherARM.totalAssets(), 1e12 + amount, "totalAssets");
        assertEq(etherARM.totalSupply(), 1e12 + expectedShares, "totalSupply");
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
        etherARM.deposit(firstAmount);

        // Sanity check state after first deposit
        assertEq(etherARM.balanceOf(alice), expectedFirstShares, "alice shares pre");
        assertEq(etherARM.totalAssets(), 1e12 + firstAmount, "totalAssets pre");
        assertEq(etherARM.totalSupply(), 1e12 + expectedFirstShares, "totalSupply pre");

        // Expect events for second deposit (by Bobby)
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(bobby, address(etherARM), secondAmount);
        vm.expectEmit({emitter: address(etherARM)});
        emit IERC20.Transfer(address(0), bobby, expectedSecondShares);
        vm.expectEmit({emitter: address(etherARM)});
        emit AbstractARM.Deposit(bobby, secondAmount, expectedSecondShares);

        // When: second deposit by Bobby
        vm.prank(bobby);
        etherARM.deposit(secondAmount);

        // Then
        assertEq(weth.balanceOf(alice), 99 ether, "alice weth");
        assertEq(weth.balanceOf(bobby), 97 ether, "bobby weth");
        assertEq(etherARM.balanceOf(alice), expectedFirstShares, "alice shares");
        assertEq(etherARM.balanceOf(bobby), expectedSecondShares, "bobby shares");
        assertEq(etherARM.totalAssets(), 1e12 + firstAmount + secondAmount, "totalAssets");
        assertEq(etherARM.totalSupply(), 1e12 + expectedFirstShares + expectedSecondShares, "totalSupply");
    }

    function test_Deposit_Default_WithCap() public {
        // Given
        uint256 amount = 1 ether;
        uint256 expectedShares = amount; // 1:1 for simplicity
        assertEq(etherARM.convertToShares(amount), expectedShares, "convertToShares");
        assertEq(etherARM.totalAssets(), 1e12, "totalAssets pre");
        assertEq(etherARM.totalSupply(), 1e12, "totalSupply pre");

        // Set a cap that allows the deposit
        address[] memory lps = new address[](1);
        lps[0] = alice;
        vm.startPrank(governor);
        capManager.setLiquidityProviderCaps(lps, 10 ether);
        capManager.setTotalAssetsCap(10 ether);
        etherARM.setCapManager(address(capManager));
        vm.stopPrank();

        // Expect
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(etherARM), amount);
        vm.expectEmit({emitter: address(etherARM)});
        emit IERC20.Transfer(address(0), alice, expectedShares);
        vm.expectEmit({emitter: address(etherARM)});
        emit AbstractARM.Deposit(alice, amount, expectedShares);

        // When
        vm.prank(alice);
        etherARM.deposit(amount);

        // Then
        assertEq(weth.balanceOf(alice), 99 ether, "alice weth");
        assertEq(etherARM.balanceOf(alice), expectedShares, "alice shares");
        assertEq(etherARM.totalAssets(), 1e12 + amount, "totalAssets");
        assertEq(etherARM.totalSupply(), 1e12 + expectedShares, "totalSupply");
    }

    function test_Deposit_DifferentReceiver() public {
        // Given
        uint256 amount = 1 ether;
        uint256 expectedShares = amount; // 1:1 for simplicity
        assertEq(etherARM.convertToShares(amount), expectedShares, "convertToShares");
        assertEq(etherARM.totalAssets(), 1e12, "totalAssets pre");
        assertEq(etherARM.totalSupply(), 1e12, "totalSupply pre");
        deal(address(weth), bobby, 100 ether);

        // Expect
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(etherARM), amount);
        vm.expectEmit({emitter: address(etherARM)});
        emit IERC20.Transfer(address(0), bobby, expectedShares);
        vm.expectEmit({emitter: address(etherARM)});
        emit AbstractARM.Deposit(bobby, amount, expectedShares);

        // When
        vm.prank(alice);
        etherARM.deposit(amount, bobby);

        // Then
        assertEq(weth.balanceOf(alice), 99 ether, "alice weth");
        assertEq(weth.balanceOf(bobby), 100 ether, "bobby weth");
        assertEq(etherARM.balanceOf(alice), 0, "alice shares");
        assertEq(etherARM.balanceOf(bobby), expectedShares, "bobby shares");
        assertEq(etherARM.totalAssets(), 1e12 + amount, "totalAssets");
        assertEq(etherARM.totalSupply(), 1e12 + expectedShares, "totalSupply");
    }

    function test_Deposit_SharesAreAbove1() public {
        aliceFirstDeposit();
        uint256 rewards = 1.235679154167425791 ether;
        // Simulate rewards by donating WETH directly to the ARM. totalSupply stays at 1e12 + 100 ether,
        // while totalAssets grows by `rewards`, so 1 share is now worth >1 asset.
        deal(address(weth), address(etherARM), weth.balanceOf(address(etherARM)) + rewards);

        // Given
        uint256 amount = 10 ether;
        uint256 expectedShares = amount.mulDiv(100 ether + 1e12, 100 ether + 1e12 + rewards, Math.Rounding.Floor);
        assertEq(etherARM.convertToShares(amount), expectedShares, "convertToShares");
        assertLt(expectedShares, amount, "shares < assets");

        // Fund Bobby for the deposit
        deal(address(weth), bobby, amount);

        uint256 totalAssetsBefore = etherARM.totalAssets();
        uint256 totalSupplyBefore = etherARM.totalSupply();

        // Expect
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(bobby, address(etherARM), amount);
        vm.expectEmit({emitter: address(etherARM)});
        emit IERC20.Transfer(address(0), bobby, expectedShares);
        vm.expectEmit({emitter: address(etherARM)});
        emit AbstractARM.Deposit(bobby, amount, expectedShares);

        // When
        vm.prank(bobby);
        etherARM.deposit(amount);

        // Then
        assertEq(weth.balanceOf(bobby), 0, "bobby weth");
        assertEq(etherARM.balanceOf(bobby), expectedShares, "bobby shares");
        assertEq(etherARM.totalAssets(), totalAssetsBefore + amount, "totalAssets");
        assertEq(etherARM.totalSupply(), totalSupplyBefore + expectedShares, "totalSupply");
    }

    //////////////////////////////////////////////////////
    /// ---                  REVERTS                   ---
    //////////////////////////////////////////////////////
    function test_Deposit_RevertWhen_Insolvent() public {
        // Alice deposit 100 ether to be solvent
        aliceFirstDeposit();

        // Alice withdraw some share to prevent `reservedWithdrawLiquidity == 0`.
        vm.prank(alice);
        etherARM.requestRedeem(50 ether);

        // Simulate a loss by reducing the total assets (e.g., due to a failed strategy or slashing)
        uint256 balance = weth.balanceOf(address(etherARM));
        vm.prank(address(etherARM));
        weth.transfer(address(0), balance - 10 wei); // Leave a tiny amount to avoid zero total assets

        // Expect revert due to insolvency
        vm.prank(alice);
        vm.expectRevert(AbstractARM.Insolvent.selector);
        etherARM.deposit(1 ether);
    }
}
