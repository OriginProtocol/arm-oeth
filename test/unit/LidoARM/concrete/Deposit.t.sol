// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_LidoARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Unit_LidoARM_Deposit_Test is Unit_LidoARM_Shared_Test {
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
        assertEq(lidoARM.convertToShares(amount), expectedShares, "convertToShares");
        assertEq(lidoARM.totalAssets(), 1e12, "totalAssets pre");
        assertEq(lidoARM.totalSupply(), 1e12, "totalSupply pre");
        assertEq(lidoARM.previewDeposit(amount), expectedShares, "previewDeposit");

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
        assertEq(weth.balanceOf(alice), 99 ether, "alice weth");
        assertEq(lidoARM.balanceOf(alice), expectedShares, "alice shares");
        assertEq(lidoARM.totalAssets(), 1e12 + amount, "totalAssets");
        assertEq(lidoARM.totalSupply(), 1e12 + expectedShares, "totalSupply");
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
        assertEq(lidoARM.balanceOf(alice), expectedFirstShares, "alice shares pre");
        assertEq(lidoARM.totalAssets(), 1e12 + firstAmount, "totalAssets pre");
        assertEq(lidoARM.totalSupply(), 1e12 + expectedFirstShares, "totalSupply pre");

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
        assertEq(weth.balanceOf(alice), 99 ether, "alice weth");
        assertEq(weth.balanceOf(bobby), 97 ether, "bobby weth");
        assertEq(lidoARM.balanceOf(alice), expectedFirstShares, "alice shares");
        assertEq(lidoARM.balanceOf(bobby), expectedSecondShares, "bobby shares");
        assertEq(lidoARM.totalAssets(), 1e12 + firstAmount + secondAmount, "totalAssets");
        assertEq(lidoARM.totalSupply(), 1e12 + expectedFirstShares + expectedSecondShares, "totalSupply");
    }

    function test_Deposit_Default_WithCap() public {
        // Given
        uint256 amount = 1 ether;
        uint256 expectedShares = amount; // 1:1 for simplicity
        assertEq(lidoARM.convertToShares(amount), expectedShares, "convertToShares");
        assertEq(lidoARM.totalAssets(), 1e12, "totalAssets pre");
        assertEq(lidoARM.totalSupply(), 1e12, "totalSupply pre");

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
        assertEq(weth.balanceOf(alice), 99 ether, "alice weth");
        assertEq(lidoARM.balanceOf(alice), expectedShares, "alice shares");
        assertEq(lidoARM.totalAssets(), 1e12 + amount, "totalAssets");
        assertEq(lidoARM.totalSupply(), 1e12 + expectedShares, "totalSupply");
    }

    function test_Deposit_DifferentReceiver() public {
        // Given
        uint256 amount = 1 ether;
        uint256 expectedShares = amount; // 1:1 for simplicity
        assertEq(lidoARM.convertToShares(amount), expectedShares, "convertToShares");
        assertEq(lidoARM.totalAssets(), 1e12, "totalAssets pre");
        assertEq(lidoARM.totalSupply(), 1e12, "totalSupply pre");
        deal(address(weth), bobby, 100 ether);

        // Expect
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(lidoARM), amount);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), bobby, expectedShares);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.Deposit(bobby, amount, expectedShares);

        // When
        vm.prank(alice);
        lidoARM.deposit(amount, bobby);

        // Then
        assertEq(weth.balanceOf(alice), 99 ether, "alice weth");
        assertEq(weth.balanceOf(bobby), 100 ether, "bobby weth");
        assertEq(lidoARM.balanceOf(alice), 0, "alice shares");
        assertEq(lidoARM.balanceOf(bobby), expectedShares, "bobby shares");
        assertEq(lidoARM.totalAssets(), 1e12 + amount, "totalAssets");
        assertEq(lidoARM.totalSupply(), 1e12 + expectedShares, "totalSupply");
    }

    function test_Deposit_SharesAreAbove1() public {
        aliceFirstDeposit();
        uint256 rewards = 1.235679154167425791 ether;
        // Simulate rewards by donating WETH directly to the ARM. totalSupply stays at 1e12 + 100 ether,
        // while totalAssets grows by `rewards`, so 1 share is now worth >1 asset.
        deal(address(weth), address(lidoARM), weth.balanceOf(address(lidoARM)) + rewards);

        // Given
        uint256 amount = 10 ether;
        uint256 expectedShares = amount.mulDiv(100 ether + 1e12, 100 ether + 1e12 + rewards, Math.Rounding.Floor);
        assertEq(lidoARM.convertToShares(amount), expectedShares, "convertToShares");
        assertLt(expectedShares, amount, "shares < assets");

        // Fund Bobby for the deposit
        deal(address(weth), bobby, amount);

        uint256 totalAssetsBefore = lidoARM.totalAssets();
        uint256 totalSupplyBefore = lidoARM.totalSupply();

        // Expect
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(bobby, address(lidoARM), amount);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), bobby, expectedShares);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.Deposit(bobby, amount, expectedShares);

        // When
        vm.prank(bobby);
        lidoARM.deposit(amount);

        // Then
        assertEq(weth.balanceOf(bobby), 0, "bobby weth");
        assertEq(lidoARM.balanceOf(bobby), expectedShares, "bobby shares");
        assertEq(lidoARM.totalAssets(), totalAssetsBefore + amount, "totalAssets");
        assertEq(lidoARM.totalSupply(), totalSupplyBefore + expectedShares, "totalSupply");
    }

    function test_Deposit_WithBackedAccruedFees() public {
        _generateFees();
        uint256 fees = lidoARM.feesAccrued();
        assertGt(fees, 0, "fees accrued");

        // Keep enough gross assets above the accrued-fee floor so deposits remain open.
        deal(address(steth), address(lidoARM), 0);
        deal(address(weth), address(lidoARM), fees + 1e12 + 1 ether);

        uint256 amount = 1 ether;
        uint256 expectedShares = lidoARM.convertToShares(amount);
        deal(address(weth), bobby, amount);

        vm.prank(bobby);
        lidoARM.deposit(amount);

        assertEq(lidoARM.balanceOf(bobby), expectedShares, "bobby shares");
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
        vm.expectRevert(AbstractARM.Insolvent.selector);
        lidoARM.deposit(1 ether);
    }

    function test_Deposit_RevertWhen_AccruedFeesUndercollateralized() public {
        _generateFees();
        uint256 fees = lidoARM.feesAccrued();
        assertGt(fees, 0, "fees accrued");
        assertEq(lidoARM.reservedWithdrawLiquidity(), 0, "no reserved withdrawals");

        // Simulate a loss that leaves accrued fees undercollateralized at the asset floor.
        deal(address(steth), address(lidoARM), 0);
        deal(address(weth), address(lidoARM), fees + 1e12);

        vm.expectRevert(AbstractARM.Insolvent.selector);
        vm.prank(alice);
        lidoARM.deposit(1 ether);
    }

    //////////////////////////////////////////////////////
    /// --- Helpers
    //////////////////////////////////////////////////////
    function _generateFees() internal {
        aliceFirstDeposit();
        addBaseAsset(steth);

        uint256 amountIn = 10 ether;
        deal(address(steth), bobby, amountIn);
        vm.prank(bobby);
        lidoARM.swapExactTokensForTokens(steth, weth, amountIn, 0, bobby);
    }
}
