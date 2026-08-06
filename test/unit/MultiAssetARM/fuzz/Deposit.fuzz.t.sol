// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @author Origin Protocol Inc
/// @notice Fuzzes LP deposits with both 6- and 18-decimal liquidity at the initial, post-yield, and
///         post-loss share-price regimes.
abstract contract Deposit_Fuzz_Test is Unit_MultiAssetARM_Shared_Test {
    using Math for uint256;

    //////////////////////////////////////////////////////
    /// ---                  SETUP                     ---
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();
        desactiveCapManager();
    }

    //////////////////////////////////////////////////////
    /// ---             Share price = 1                ---
    //////////////////////////////////////////////////////
    function testFuzz_Deposit_Amount(uint128 amount) public {
        // Initial regime: only the MIN_TOTAL_SUPPLY dead shares exist, so one whole liquidity token
        // mints one 18-decimal LP share regardless of the liquidity asset's decimals.
        // Upper bound is uint128.max because there is no SafeCast on deposit; the only revert path is
        // `ARM: insolvent`, which cannot fire here (reservedWithdrawLiquidity == 0).
        uint256 amountIn = _bound(uint256(amount), 1, type(uint128).max);

        uint256 supplyBefore = arm.totalSupply();
        uint256 assetsBefore = arm.totalAssets();
        // Expected shares computed via the same mulDiv as the contract; written explicitly so any future
        // change to convertToShares (e.g. rounding direction) shows up here.
        uint256 expectedShares = amountIn.mulDiv(supplyBefore, assetsBefore, Math.Rounding.Floor);
        uint256 expectedAtInitialRate = amountIn.mulDiv(1e18, LIQUIDITY_UNIT(), Math.Rounding.Floor);
        assertEq(expectedShares, expectedAtInitialRate, "shares at initial rate");

        deal(address(liquidity), alice, amountIn);

        // Expect events
        vm.expectEmit({emitter: address(liquidity)});
        emit IERC20.Transfer(alice, address(arm), amountIn);
        vm.expectEmit({emitter: address(arm)});
        emit IERC20.Transfer(address(0), alice, expectedShares);
        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.Deposit(alice, amountIn, expectedShares);

        // When
        vm.prank(alice);
        uint256 shares = arm.deposit(amountIn);

        // Then
        assertEq(shares, expectedShares, "shares returned");
        assertEq(arm.balanceOf(alice), expectedShares, "alice shares");
        assertEq(liquidity.balanceOf(alice), 0, "alice liquidity");
        assertEq(liquidity.balanceOf(address(arm)), assetsBefore + amountIn, "arm liquidity");
        assertEq(arm.totalAssets(), assetsBefore + amountIn, "totalAssets");
        assertEq(arm.totalSupply(), supplyBefore + expectedShares, "totalSupply");
    }

    //////////////////////////////////////////////////////
    /// ---             Share price > 1                ---
    //////////////////////////////////////////////////////
    function testFuzz_Deposit_AfterYield(uint128 fuzzedYield, uint128 amount) public {
        aliceFirstDeposit(DEFAULT_AMOUNT());

        // Lower yield bound at one token so the share price is meaningfully above par; below this, integer
        // truncation can collapse expectedShares back to amountIn on small deposits.
        // Upper bound at uint96.max keeps (supply + yield) safely inside uint128 downstream.
        uint256 yield = _bound(uint256(fuzzedYield), LIQUIDITY_UNIT(), type(uint96).max);
        deal(address(liquidity), address(arm), liquidity.balanceOf(address(arm)) + yield);

        uint256 amountIn = _bound(uint256(amount), 1, type(uint128).max);
        deal(address(liquidity), alice, amountIn);

        uint256 supplyBefore = arm.totalSupply();
        uint256 assetsBefore = arm.totalAssets();
        uint256 aliceSharesBefore = arm.balanceOf(alice);
        uint256 expectedShares = amountIn.mulDiv(supplyBefore, assetsBefore, Math.Rounding.Floor);

        uint256 sharesAtInitialRate = amountIn.mulDiv(1e18, LIQUIDITY_UNIT(), Math.Rounding.Floor);
        assertLt(expectedShares, sharesAtInitialRate, "shares below initial-rate amount after yield");

        // Expect events
        vm.expectEmit({emitter: address(liquidity)});
        emit IERC20.Transfer(alice, address(arm), amountIn);
        vm.expectEmit({emitter: address(arm)});
        emit IERC20.Transfer(address(0), alice, expectedShares);
        vm.expectEmit({emitter: address(arm)});
        emit AbstractARM.Deposit(alice, amountIn, expectedShares);

        // When
        vm.prank(alice);
        uint256 shares = arm.deposit(amountIn);

        // Then
        assertEq(shares, expectedShares, "shares returned");
        assertEq(arm.balanceOf(alice), aliceSharesBefore + expectedShares, "alice shares");
        assertEq(liquidity.balanceOf(alice), 0, "alice liquidity");
        assertEq(arm.totalAssets(), assetsBefore + amountIn, "totalAssets");
        assertEq(arm.totalSupply(), supplyBefore + expectedShares, "totalSupply");
    }

    //////////////////////////////////////////////////////
    /// ---             Share price < 1                ---
    //////////////////////////////////////////////////////
    function testFuzz_Deposit_AfterLoss(uint128 fuzzedLoss, uint128 amount) public {
        aliceFirstDeposit(DEFAULT_AMOUNT());

        // Any loss below the initial share price makes the ARM loss-impaired for new deposits.
        uint256 loss = _bound(uint256(fuzzedLoss), 1, DEFAULT_AMOUNT() - 1);
        vm.prank(address(arm));
        liquidity.transfer(address(0), loss);

        uint256 amountIn = _bound(uint256(amount), 1, type(uint128).max);
        deal(address(liquidity), alice, amountIn);

        vm.expectRevert(AbstractARM.Insolvent.selector);
        vm.prank(alice);
        arm.deposit(amountIn);
    }

    function testFuzz_Deposit_AtOrAboveRequiredBacking(uint128 fuzzedSurplus, uint128 amount) public {
        aliceFirstDeposit(DEFAULT_AMOUNT());

        uint256 requiredAssets = arm.totalSupply().mulDiv(LIQUIDITY_UNIT(), 1e18, Math.Rounding.Ceil);
        uint256 surplus = _bound(uint256(fuzzedSurplus), 0, DEFAULT_AMOUNT() * 100);
        deal(address(liquidity), address(arm), requiredAssets + surplus);

        uint256 amountIn = _bound(uint256(amount), 1, type(uint128).max);
        deal(address(liquidity), alice, amountIn);

        uint256 expectedShares = amountIn.mulDiv(arm.totalSupply(), arm.totalAssets(), Math.Rounding.Floor);
        vm.prank(alice);
        uint256 shares = arm.deposit(amountIn);

        assertEq(shares, expectedShares, "shares at or above required backing");
    }
}

contract Deposit_Fuzz_18dec_Test is Deposit_Fuzz_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

contract Deposit_Fuzz_6dec_Test is Deposit_Fuzz_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
