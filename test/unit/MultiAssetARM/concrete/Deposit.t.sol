// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";

import {AbstractARM} from "contracts/AbstractARM.sol";

/// @notice Deposit flow, run at both 18 and 6 decimal liquidity. LP shares are always 18-decimal, so the
///         share/asset scaling is `MIN_TOTAL_SUPPLY / MIN_LIQUIDITY()`: identity at 18-dec, x1e12 at 6-dec.
///         In both cases 100 liquidity tokens mint exactly 100e18 LP tokens.
abstract contract Deposit_Test is Unit_MultiAssetARM_Shared_Test {
    event Deposit(address indexed owner, uint256 assets, uint256 shares);

    function setUp() public virtual override {
        super.setUp();
        desactiveCapManager();
    }

    function _expectedFirstShares() internal pure returns (uint256) {
        return DEFAULT_AMOUNT() * MIN_TOTAL_SUPPLY / MIN_LIQUIDITY();
    }

    function test_InitialState() public view {
        assertEq(liquidity.balanceOf(address(arm)), MIN_LIQUIDITY(), "init liquidity");
        assertEq(arm.totalSupply(), MIN_TOTAL_SUPPLY, "init supply (18-dec dead shares)");
        assertEq(arm.totalAssets(), MIN_LIQUIDITY(), "init totalAssets floor");
    }

    function test_FirstDeposit_Scales() public {
        uint256 expected = _expectedFirstShares();
        assertEq(expected, 100e18, "100 liquidity tokens -> 100 LP tokens");
        assertEq(arm.previewDeposit(DEFAULT_AMOUNT()), expected, "previewDeposit");

        uint256 shares = firstDeposit(alice, DEFAULT_AMOUNT());

        assertEq(shares, expected, "shares minted");
        assertEq(arm.balanceOf(alice), expected, "alice LP balance (18-dec)");
        assertEq(liquidity.balanceOf(address(arm)), MIN_LIQUIDITY() + DEFAULT_AMOUNT(), "ARM liquidity");
        assertEq(arm.totalSupply(), MIN_TOTAL_SUPPLY + expected, "total supply");
        assertEq(arm.totalAssets(), MIN_LIQUIDITY() + DEFAULT_AMOUNT(), "totalAssets");
    }

    function test_Deposit_ToReceiver() public {
        _mint(liquidity, alice, DEFAULT_AMOUNT());
        vm.startPrank(alice);
        liquidity.approve(address(arm), type(uint256).max);
        uint256 shares = arm.deposit(DEFAULT_AMOUNT(), bobby);
        vm.stopPrank();

        assertEq(arm.balanceOf(bobby), shares, "receiver got shares");
        assertEq(arm.balanceOf(alice), 0, "depositor got none");
    }

    function test_SecondDeposit_KeepsValue() public {
        firstDeposit(alice, DEFAULT_AMOUNT());
        uint256 bobbyShares = firstDeposit(bobby, DEFAULT_AMOUNT());
        assertApproxEqRel(bobbyShares, 100e18, 1e9, "bobby ~100 LP tokens"); // 1e9/1e18 = 1e-9 tolerance
        assertLe(bobbyShares, 100e18, "rounding favors the vault");
    }

    function test_Deposit_EmitsEvent() public {
        _mint(liquidity, alice, DEFAULT_AMOUNT());
        vm.startPrank(alice);
        liquidity.approve(address(arm), type(uint256).max);
        vm.expectEmit(true, false, false, true, address(arm));
        emit Deposit(alice, DEFAULT_AMOUNT(), _expectedFirstShares());
        arm.deposit(DEFAULT_AMOUNT());
        vm.stopPrank();
    }

    function test_Deposit_WithBackedAccruedFees() public {
        uint256 fees = _generateFees();

        // Keep gross assets above the accrued-fee floor so deposits remain open.
        _setArmBalances(fees + MIN_LIQUIDITY() + LIQUIDITY_UNIT(), 0);

        uint256 amount = LIQUIDITY_UNIT();
        uint256 expectedShares = arm.convertToShares(amount);
        _mint(liquidity, bobby, amount);

        vm.prank(bobby);
        uint256 shares = arm.deposit(amount);

        assertEq(shares, expectedShares, "shares returned");
        assertEq(arm.balanceOf(bobby), expectedShares, "bobby shares");
    }

    function test_Deposit_RevertWhen_AccruedFeesUndercollateralized() public {
        uint256 fees = _generateFees();
        assertEq(arm.reservedWithdrawLiquidity(), 0, "no reserved withdrawals");

        // Simulate a loss that leaves accrued fees undercollateralized below the asset floor.
        _setArmBalances(fees + MIN_LIQUIDITY() - 1, 0);

        vm.expectRevert(AbstractARM.Insolvent.selector);
        vm.prank(alice);
        arm.deposit(LIQUIDITY_UNIT());
    }

    function test_Deposit_WhenAccruedFeesExactlyBacked() public {
        uint256 fees = _generateFees();
        assertEq(arm.reservedWithdrawLiquidity(), 0, "no reserved withdrawals");

        _setArmBalances(fees + MIN_LIQUIDITY(), 0);

        uint256 amount = LIQUIDITY_UNIT();
        uint256 expectedShares = amount * arm.totalSupply() / MIN_LIQUIDITY();
        _mint(liquidity, bobby, amount);

        vm.prank(bobby);
        uint256 shares = arm.deposit(amount);

        assertEq(shares, expectedShares, "shares returned");
        assertEq(arm.balanceOf(bobby), expectedShares, "bobby shares");
        assertEq(arm.totalAssets(), MIN_LIQUIDITY() + amount, "net assets increase by deposit");
    }

    function _generateFees() internal returns (uint256 fees) {
        firstDeposit(alice, DEFAULT_AMOUNT());

        uint256 amountIn = 10 ether;
        dealBaseToUser(peg18, bobby, amountIn);
        vm.prank(bobby);
        arm.swapExactTokensForTokens(peg18, liquidity, amountIn, 0, bobby);

        fees = arm.feesAccrued();
        assertGt(fees, 0, "fees accrued");
    }

    function _setArmBalances(uint256 liquidityAmount, uint256 peg18Amount) internal {
        uint256 liquidityBalance = liquidity.balanceOf(address(arm));
        if (liquidityBalance != 0) {
            vm.prank(address(arm));
            liquidity.transfer(address(0), liquidityBalance);
        }

        uint256 peg18Balance = peg18.balanceOf(address(arm));
        if (peg18Balance != 0) {
            vm.prank(address(arm));
            peg18.transfer(address(0), peg18Balance);
        }

        if (liquidityAmount != 0) _mint(liquidity, address(arm), liquidityAmount);
        if (peg18Amount != 0) _mint(peg18, address(arm), peg18Amount);
    }
}

contract Deposit_18dec_Test is Deposit_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

contract Deposit_6dec_Test is Deposit_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
