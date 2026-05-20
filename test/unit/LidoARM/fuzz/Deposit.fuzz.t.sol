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

/// @author Origin Protocol Inc
/// @notice Fuzzes LP deposits at three share-price regimes (1:1, post-yield, post-loss) to confirm the
///         ERC-4626-style mint formula, balances, and totalAssets/totalSupply accounting stay consistent
///         across the full amount range.
contract Unit_Fuzz_LidoARM_Deposit_Test is Unit_LidoARM_Shared_Test {
    using Math for uint256;

    //////////////////////////////////////////////////////
    /// ---                  SETUP                     ---
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
        desactiveCapManager();
    }

    //////////////////////////////////////////////////////
    /// ---             Share price = 1                ---
    //////////////////////////////////////////////////////
    function testFuzz_Deposit_Amount(uint128 amount) public {
        // 1:1 regime: only the MIN_TOTAL_SUPPLY dead-shares exist, so shares == assets exactly.
        // Upper bound is uint128.max because there is no SafeCast on deposit; the only revert path is
        // `ARM: insolvent`, which cannot fire here (reservedWithdrawLiquidity == 0).
        uint256 amountIn = _bound(uint256(amount), 1, type(uint128).max);

        uint256 supplyBefore = lidoARM.totalSupply();
        uint256 assetsBefore = lidoARM.totalAssets();
        // Expected shares computed via the same mulDiv as the contract; written explicitly so any future
        // change to convertToShares (e.g. rounding direction) shows up here.
        uint256 expectedShares = amountIn.mulDiv(supplyBefore, assetsBefore, Math.Rounding.Floor);
        // Sanity: in the 1:1 setup state shares must equal assets.
        assertEq(expectedShares, amountIn, "expectedShares == amountIn at 1:1");

        deal(address(weth), alice, amountIn);

        // Expect events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(lidoARM), amountIn);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), alice, expectedShares);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.Deposit(alice, amountIn, expectedShares);

        // When
        vm.prank(alice);
        uint256 shares = lidoARM.deposit(amountIn);

        // Then
        assertEq(shares, expectedShares, "shares returned");
        assertEq(lidoARM.balanceOf(alice), expectedShares, "alice shares");
        assertEq(weth.balanceOf(alice), 0, "alice weth");
        assertEq(weth.balanceOf(address(lidoARM)), assetsBefore + amountIn, "arm weth");
        assertEq(lidoARM.totalAssets(), assetsBefore + amountIn, "totalAssets");
        assertEq(lidoARM.totalSupply(), supplyBefore + expectedShares, "totalSupply");
    }

    //////////////////////////////////////////////////////
    /// ---             Share price > 1                ---
    //////////////////////////////////////////////////////
    function testFuzz_Deposit_AfterYield(uint128 fuzzedYield, uint128 amount) public {
        aliceFirstDeposit(100 ether);

        // Lower yield bound at 1 ether so the share price is meaningfully above 1; below this, integer
        // truncation can collapse expectedShares back to amountIn on small deposits.
        // Upper bound at uint96.max keeps (supply + yield) safely inside uint128 downstream.
        uint256 yield = _bound(uint256(fuzzedYield), 1 ether, type(uint96).max);
        deal(address(weth), address(lidoARM), weth.balanceOf(address(lidoARM)) + yield);

        uint256 amountIn = _bound(uint256(amount), 1, type(uint128).max);
        deal(address(weth), alice, amountIn);

        uint256 supplyBefore = lidoARM.totalSupply();
        uint256 assetsBefore = lidoARM.totalAssets();
        uint256 aliceSharesBefore = lidoARM.balanceOf(alice);
        uint256 expectedShares = amountIn.mulDiv(supplyBefore, assetsBefore, Math.Rounding.Floor);

        // Property: yield > 0 ⇒ totalSupply < totalAssets ⇒ floor(amountIn * S / A) < amountIn strictly,
        // since amountIn * S < amountIn * A and integer division can only floor. Holds for amountIn >= 1.
        assertLt(expectedShares, amountIn, "shares < amountIn after yield");

        // Expect events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(lidoARM), amountIn);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), alice, expectedShares);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.Deposit(alice, amountIn, expectedShares);

        // When
        vm.prank(alice);
        uint256 shares = lidoARM.deposit(amountIn);

        // Then
        assertEq(shares, expectedShares, "shares returned");
        assertEq(lidoARM.balanceOf(alice), aliceSharesBefore + expectedShares, "alice shares");
        assertEq(weth.balanceOf(alice), 0, "alice weth");
        assertEq(lidoARM.totalAssets(), assetsBefore + amountIn, "totalAssets");
        assertEq(lidoARM.totalSupply(), supplyBefore + expectedShares, "totalSupply");
    }

    //////////////////////////////////////////////////////
    /// ---             Share price < 1                ---
    //////////////////////////////////////////////////////
    function testFuzz_Deposit_AfterLoss(uint128 fuzzedLoss, uint128 amount) public {
        aliceFirstDeposit(100 ether);

        // Bound loss strictly below the LP liquid asset to keep totalAssets > MIN_TOTAL_SUPPLY, otherwise
        // the totalAssets() clamp at AbstractARM.sol:901 kicks in and the simple mulDiv expectation no
        // longer matches the contract's view. The insolvency require passes because reservedWithdrawLiquidity == 0.
        uint256 loss = _bound(uint256(fuzzedLoss), 1, 100 ether - 1);
        vm.prank(address(lidoARM));
        weth.transfer(address(0), loss);

        uint256 amountIn = _bound(uint256(amount), 1, type(uint128).max);
        deal(address(weth), alice, amountIn);

        uint256 supplyBefore = lidoARM.totalSupply();
        uint256 assetsBefore = lidoARM.totalAssets();
        uint256 aliceSharesBefore = lidoARM.balanceOf(alice);
        uint256 expectedShares = amountIn.mulDiv(supplyBefore, assetsBefore, Math.Rounding.Floor);

        // Property: loss > 0 ⇒ share price < 1 ⇒ shares >= amountIn. Equality only on inputs small enough
        // for the spread to truncate; for any non-trivial amountIn the inequality is strict.
        assertGe(expectedShares, amountIn, "shares >= amountIn after loss");

        // Expect events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(lidoARM), amountIn);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), alice, expectedShares);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.Deposit(alice, amountIn, expectedShares);

        // When
        vm.prank(alice);
        uint256 shares = lidoARM.deposit(amountIn);

        // Then
        assertEq(shares, expectedShares, "shares returned");
        assertEq(lidoARM.balanceOf(alice), aliceSharesBefore + expectedShares, "alice shares");
        assertEq(weth.balanceOf(alice), 0, "alice weth");
        assertEq(lidoARM.totalAssets(), assetsBefore + amountIn, "totalAssets");
        assertEq(lidoARM.totalSupply(), supplyBefore + expectedShares, "totalSupply");
    }
}
