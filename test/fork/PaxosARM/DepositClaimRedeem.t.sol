// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/PaxosARM/shared/Shared.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

/// @notice Fork tests for the LP flow (deposit / requestRedeem / claimRedeem) on the Paxos
///         MultiAssetARM. The setup override keeps the ARM free of base-asset inventory so assets
///         per share stays at the initial rate (1 USDC of 6 decimals = 1e12 shares of 18 decimals)
///         and all expected amounts are exact.
contract Fork_Concrete_PaxosARM_DepositClaimRedeem_Test_ is Fork_Shared_Test {
    uint256 public constant DEPOSIT_AMOUNT = 10_000e6;
    /// @notice Shares (18 decimals) minted per USDC (6 decimals) at the initial rate.
    uint256 public constant SHARES_PER_USDC = 1e12;

    /// @dev Register the base assets but skip the ARM's USDC deposit and PYUSD/USDG donations so
    ///      the share price stays exactly at the initial rate.
    function _ignite() internal override {
        deal(address(usdc), address(this), 1_000_000e6);
        usdc.approve(address(arm), type(uint256).max);

        vm.startPrank(arm.owner());
        arm.addBaseAsset(
            address(pyusd),
            address(pyusdAdapter),
            BUY_PRICE,
            SELL_PRICE,
            type(uint128).max,
            type(uint128).max,
            CROSS_PRICE,
            true
        );
        arm.addBaseAsset(
            address(usdg),
            address(usdgAdapter),
            BUY_PRICE,
            SELL_PRICE,
            type(uint128).max,
            type(uint128).max,
            CROSS_PRICE,
            true
        );
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////
    /// --- DEPOSIT
    //////////////////////////////////////////////////////
    function test_Deposit_MintsPreviewShares() public {
        uint256 expectedShares = arm.previewDeposit(DEPOSIT_AMOUNT);
        assertEq(expectedShares, DEPOSIT_AMOUNT * SHARES_PER_USDC, "previewDeposit at initial rate");

        uint256 usdcBefore = usdc.balanceOf(address(this));
        uint256 totalAssetsBefore = arm.totalAssets();
        uint256 totalSupplyBefore = arm.totalSupply();

        uint256 shares = arm.deposit(DEPOSIT_AMOUNT);

        assertEq(shares, expectedShares, "shares == previewDeposit");
        assertEq(arm.balanceOf(address(this)), expectedShares, "LP share balance");
        assertEq(usdc.balanceOf(address(this)), usdcBefore - DEPOSIT_AMOUNT, "USDC pulled from depositor");
        assertEq(arm.totalAssets(), totalAssetsBefore + DEPOSIT_AMOUNT, "totalAssets increased");
        assertEq(arm.totalSupply(), totalSupplyBefore + expectedShares, "totalSupply increased");
    }

    //////////////////////////////////////////////////////
    /// --- REQUEST REDEEM
    //////////////////////////////////////////////////////
    function test_RequestRedeem_EscrowsSharesAndReservesLiquidity() public {
        uint256 shares = arm.deposit(DEPOSIT_AMOUNT);

        (uint256 requestId, uint256 assets) = arm.requestRedeem(shares);

        assertEq(requestId, 0, "first request id");
        assertEq(assets, DEPOSIT_AMOUNT, "assets at initial rate");

        // Shares are escrowed on the ARM, not burned.
        assertEq(arm.balanceOf(address(this)), 0, "LP shares escrowed away from redeemer");
        assertEq(arm.balanceOf(address(arm)), shares, "LP shares escrowed on the ARM");

        // The request-time payout is reserved against swaps and fee collection.
        assertEq(arm.reservedWithdrawLiquidity(), DEPOSIT_AMOUNT, "liquidity reserved");

        (address withdrawer, bool claimed, uint40 claimTimestamp, uint128 requestAssets, uint128 queued) =
            arm.withdrawalRequests(requestId);
        assertEq(withdrawer, address(this), "withdrawer");
        assertEq(claimed, false, "not claimed");
        assertEq(claimTimestamp, block.timestamp + 10 minutes, "claimable after the 10 min delay");
        assertEq(requestAssets, DEPOSIT_AMOUNT, "request assets");
        assertEq(queued, shares, "queued shares");
    }

    //////////////////////////////////////////////////////
    /// --- CLAIM REDEEM
    //////////////////////////////////////////////////////
    function test_ClaimRedeem_AfterClaimDelay() public {
        uint256 shares = arm.deposit(DEPOSIT_AMOUNT);
        (uint256 requestId,) = arm.requestRedeem(shares);

        skip(10 minutes);

        uint256 usdcBefore = usdc.balanceOf(address(this));
        uint256 totalSupplyBefore = arm.totalSupply();

        uint256 assets = arm.claimRedeem(requestId);

        assertEq(assets, DEPOSIT_AMOUNT, "full USDC payout");
        assertEq(usdc.balanceOf(address(this)), usdcBefore + DEPOSIT_AMOUNT, "USDC returned to redeemer");
        assertEq(arm.reservedWithdrawLiquidity(), 0, "reservation released");
        assertEq(arm.totalSupply(), totalSupplyBefore - shares, "escrowed shares burned");

        (, bool claimed,,,) = arm.withdrawalRequests(requestId);
        assertEq(claimed, true, "request marked claimed");
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_ClaimRedeem_Because_ClaimDelayNotMet() public {
        uint256 shares = arm.deposit(DEPOSIT_AMOUNT);
        (uint256 requestId,) = arm.requestRedeem(shares);

        // One second before the claim timestamp.
        skip(10 minutes - 1);

        vm.expectRevert(AbstractARM.ClaimDelayNotMet.selector);
        arm.claimRedeem(requestId);
    }
}
