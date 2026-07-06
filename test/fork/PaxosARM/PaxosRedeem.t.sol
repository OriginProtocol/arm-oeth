// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/PaxosARM/shared/Shared.sol";

// Contracts
import {PaxosAssetAdapter} from "contracts/adapters/PaxosAssetAdapter.sol";

// Interfaces
import {Mainnet} from "src/contracts/utils/Addresses.sol";
import {IERC20} from "contracts/Interfaces.sol";

/// @notice Fork tests for the Paxos redemption flow: requestBaseAssetRedeem pulls the base asset
///         into the adapter, submitPaxosRedeem sends it to the (mocked) Paxos recipient, off-chain
///         settlement is simulated by dealing USDC 1:1 to the adapter, and claimBaseAssetRedeem
///         returns the settled USDC to the ARM.
contract Fork_Concrete_PaxosARM_PaxosRedeem_Test_ is Fork_Shared_Test {
    uint256 public constant AMOUNT = 10_000e6;
    bytes32 public constant PAXOS_ID = bytes32("paxos-redemption-id");

    //////////////////////////////////////////////////////
    /// --- ADAPTER VIEWS
    //////////////////////////////////////////////////////
    function test_AdapterViews_AgainstRealTokens() public view {
        // Real Paxos tokens on the fork have 6 decimals, matching USDC.
        assertEq(pyusd.decimals(), 6, "PYUSD decimals");
        assertEq(usdg.decimals(), 6, "USDG decimals");
        assertEq(usdc.decimals(), 6, "USDC decimals");

        // The adapters redeem into USDC and convert 1:1 both ways.
        assertEq(pyusdAdapter.asset(), Mainnet.USDC, "PYUSD adapter asset");
        assertEq(usdgAdapter.asset(), Mainnet.USDC, "USDG adapter asset");
        assertEq(pyusdAdapter.convertToAssets(123e6), 123e6, "PYUSD convertToAssets 1:1");
        assertEq(pyusdAdapter.convertToShares(123e6), 123e6, "PYUSD convertToShares 1:1");
        assertEq(usdgAdapter.convertToAssets(123e6), 123e6, "USDG convertToAssets 1:1");
        assertEq(usdgAdapter.convertToShares(123e6), 123e6, "USDG convertToShares 1:1");

        // Adapter wiring.
        assertEq(address(pyusdAdapter.baseAsset()), Mainnet.PYUSD, "PYUSD adapter base asset");
        assertEq(address(usdgAdapter.baseAsset()), Mainnet.USDG, "USDG adapter base asset");
        assertEq(pyusdAdapter.arm(), address(arm), "PYUSD adapter ARM");
        assertEq(usdgAdapter.arm(), address(arm), "USDG adapter ARM");
        assertEq(address(_adapter(pyusd)), address(pyusdAdapter), "ARM config PYUSD adapter");
        assertEq(address(_adapter(usdg)), address(usdgAdapter), "ARM config USDG adapter");
        assertEq(pyusdAdapter.paxosRecipient(), paxosRecipient, "PYUSD adapter Paxos recipient");
        assertEq(usdgAdapter.paxosRecipient(), paxosRecipient, "USDG adapter Paxos recipient");
    }

    //////////////////////////////////////////////////////
    /// --- REQUEST
    //////////////////////////////////////////////////////
    function test_RequestBaseAssetRedeem_MovesBaseToAdapter() public {
        uint256 totalAssetsBefore = arm.totalAssets();
        uint256 armBaseBefore = pyusd.balanceOf(address(arm));

        vm.prank(operator);
        (uint256 sharesRequested, uint256 assetsExpected) = arm.requestBaseAssetRedeem(address(pyusd), AMOUNT);

        assertEq(sharesRequested, AMOUNT, "sharesRequested");
        assertEq(assetsExpected, AMOUNT, "assetsExpected 1:1");
        assertEq(pyusd.balanceOf(address(arm)), armBaseBefore - AMOUNT, "ARM PYUSD drained");
        assertEq(pyusd.balanceOf(address(pyusdAdapter)), AMOUNT, "adapter PYUSD funded");
        assertEq(pyusdAdapter.pendingShares(), AMOUNT, "adapter pendingShares");
        assertEq(pyusdAdapter.settlingShares(), 0, "nothing settling yet");
        assertEq(_pendingRedeemAssets(pyusd), AMOUNT, "config pendingRedeemAssets");
        // The base asset moved into the adapter queue at the same cross-price valuation, so
        // totalAssets is unchanged (1 wei of headroom for split floor divisions).
        assertApproxEqAbs(arm.totalAssets(), totalAssetsBefore, 1, "totalAssets unchanged");
    }

    //////////////////////////////////////////////////////
    /// --- SUBMIT
    //////////////////////////////////////////////////////
    function test_SubmitPaxosRedeem_SendsBaseToPaxosRecipient() public {
        vm.prank(operator);
        arm.requestBaseAssetRedeem(address(pyusd), AMOUNT);

        uint256 totalAssetsBefore = arm.totalAssets();

        vm.prank(operator);
        pyusdAdapter.submitPaxosRedeem(AMOUNT, PAXOS_ID);

        assertEq(pyusdAdapter.pendingShares(), 0, "pending moved to settling");
        assertEq(pyusdAdapter.settlingShares(), AMOUNT, "adapter settlingShares");
        assertEq(pyusd.balanceOf(address(pyusdAdapter)), 0, "adapter PYUSD sent away");
        assertEq(pyusd.balanceOf(paxosRecipient), AMOUNT, "Paxos recipient funded");
        // The ARM still values the redemption through pendingRedeemAssets, so nothing changes.
        assertEq(_pendingRedeemAssets(pyusd), AMOUNT, "config pendingRedeemAssets unchanged");
        assertEq(arm.totalAssets(), totalAssetsBefore, "totalAssets unchanged");
    }

    //////////////////////////////////////////////////////
    /// --- CLAIM
    //////////////////////////////////////////////////////
    function test_ClaimBaseAssetRedeem_AfterSettlement() public {
        vm.prank(operator);
        arm.requestBaseAssetRedeem(address(pyusd), AMOUNT);
        vm.prank(operator);
        pyusdAdapter.submitPaxosRedeem(AMOUNT, PAXOS_ID);

        // Paxos settles USDC 1:1 to the adapter.
        _settle(pyusdAdapter, AMOUNT);

        uint256 totalAssetsBefore = arm.totalAssets();
        uint256 armUsdcBefore = usdc.balanceOf(address(arm));

        vm.prank(operator);
        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) =
            arm.claimBaseAssetRedeem(address(pyusd), AMOUNT);

        assertEq(sharesClaimed, AMOUNT, "sharesClaimed");
        assertEq(assetsExpected, AMOUNT, "assetsExpected");
        assertEq(assetsReceived, AMOUNT, "assetsReceived");
        assertEq(usdc.balanceOf(address(arm)), armUsdcBefore + AMOUNT, "USDC back in the ARM");
        assertEq(usdc.balanceOf(address(pyusdAdapter)), 0, "adapter USDC drained");
        assertEq(pyusdAdapter.settlingShares(), 0, "settling cleared");
        assertEq(_pendingRedeemAssets(pyusd), 0, "config pendingRedeemAssets cleared");

        // _availableAssets valued the queue at `AMOUNT * crossPrice / PRICE_SCALE` and now holds
        // the full `AMOUNT` in USDC, so the cross-price discount is released into totalAssets.
        uint256 expectedRelease = AMOUNT - (AMOUNT * CROSS_PRICE / PRICE_SCALE);
        assertEq(arm.totalAssets(), totalAssetsBefore + expectedRelease, "cross-price discount released");
        assertApproxEqAbs(
            arm.totalAssets(), totalAssetsBefore + (PRICE_SCALE - CROSS_PRICE) * AMOUNT / PRICE_SCALE, 1, "~0.1% gain"
        );
    }

    function test_RevertWhen_ClaimBaseAssetRedeem_Because_NotSettled() public {
        vm.prank(operator);
        arm.requestBaseAssetRedeem(address(pyusd), AMOUNT);
        vm.prank(operator);
        pyusdAdapter.submitPaxosRedeem(AMOUNT, PAXOS_ID);

        // Submitted to Paxos but no USDC settled on the adapter yet.
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaxosAssetAdapter.InsufficientSettledAssets.selector, AMOUNT, 0));
        arm.claimBaseAssetRedeem(address(pyusd), AMOUNT);
    }

    function test_RevertWhen_ClaimBaseAssetRedeem_Because_NotSubmitted() public {
        vm.prank(operator);
        arm.requestBaseAssetRedeem(address(pyusd), AMOUNT);

        // Requested but never submitted to Paxos: nothing is settling.
        vm.prank(operator);
        vm.expectRevert(PaxosAssetAdapter.RedeemAmountTooHigh.selector);
        arm.claimBaseAssetRedeem(address(pyusd), AMOUNT);
    }

    //////////////////////////////////////////////////////
    /// --- LIFECYCLES
    //////////////////////////////////////////////////////
    function test_FullLifecycle_Pyusd() public {
        _fullLifecycle(pyusd, pyusdAdapter);
    }

    function test_FullLifecycle_Usdg() public {
        _fullLifecycle(usdg, usdgAdapter);
    }

    function test_PartialLifecycle_Usdg() public {
        uint256 half = AMOUNT / 2;

        vm.prank(operator);
        arm.requestBaseAssetRedeem(address(usdg), AMOUNT);

        // Submit / settle / claim only the first half.
        vm.prank(operator);
        usdgAdapter.submitPaxosRedeem(half, bytes32("paxos-usdg-1"));

        assertEq(usdgAdapter.pendingShares(), AMOUNT - half, "half still pending");
        assertEq(usdgAdapter.settlingShares(), half, "half settling");
        assertEq(usdg.balanceOf(paxosRecipient), half, "half sent to Paxos");
        assertEq(usdg.balanceOf(address(usdgAdapter)), AMOUNT - half, "half kept in the adapter");

        _settle(usdgAdapter, half);

        uint256 armUsdcBefore = usdc.balanceOf(address(arm));
        vm.prank(operator);
        (uint256 sharesClaimed,, uint256 assetsReceived) = arm.claimBaseAssetRedeem(address(usdg), half);

        assertEq(sharesClaimed, half, "half claimed");
        assertEq(assetsReceived, half, "half received");
        assertEq(usdc.balanceOf(address(arm)), armUsdcBefore + half, "half USDC in the ARM");
        assertEq(usdgAdapter.settlingShares(), 0, "settling cleared");
        assertEq(_pendingRedeemAssets(usdg), AMOUNT - half, "half still expected from the queue");

        // Submit / settle / claim the second half.
        vm.prank(operator);
        usdgAdapter.submitPaxosRedeem(AMOUNT - half, bytes32("paxos-usdg-2"));
        _settle(usdgAdapter, AMOUNT - half);
        vm.prank(operator);
        arm.claimBaseAssetRedeem(address(usdg), AMOUNT - half);

        assertEq(usdc.balanceOf(address(arm)), armUsdcBefore + AMOUNT, "full USDC in the ARM");
        assertEq(usdg.balanceOf(paxosRecipient), AMOUNT, "full amount sent to Paxos");
        assertEq(usdgAdapter.pendingShares(), 0, "nothing pending");
        assertEq(usdgAdapter.settlingShares(), 0, "nothing settling");
        assertEq(_pendingRedeemAssets(usdg), 0, "queue fully claimed");
    }

    //////////////////////////////////////////////////////
    /// --- SHARED LIFECYCLE LOGIC
    //////////////////////////////////////////////////////
    /// @dev swap in -> request -> submit -> settle -> claim, asserting totalAssets never decreases.
    function _fullLifecycle(IERC20 token, PaxosAssetAdapter adapter) internal {
        uint256 floor_ = arm.totalAssets();

        // 1. Trader sells the base asset to the ARM at the discounted buy price.
        arm.swapExactTokensForTokens(token, usdc, AMOUNT, 0, address(this));
        floor_ = _assertTotalAssetsNeverDecreases(floor_);

        // 2. Operator queues the base asset for Paxos redemption.
        vm.prank(operator);
        arm.requestBaseAssetRedeem(address(token), AMOUNT);
        floor_ = _assertTotalAssetsNeverDecreases(floor_);

        // 3. Operator submits the queued amount to the (mocked) Paxos recipient.
        vm.prank(operator);
        adapter.submitPaxosRedeem(AMOUNT, PAXOS_ID);
        floor_ = _assertTotalAssetsNeverDecreases(floor_);

        // 4. Paxos settles USDC 1:1 to the adapter (off-chain queue is mocked).
        _settle(adapter, AMOUNT);
        floor_ = _assertTotalAssetsNeverDecreases(floor_);

        // 5. Operator claims the settled USDC into the ARM.
        uint256 armUsdcBefore = usdc.balanceOf(address(arm));
        vm.prank(operator);
        (uint256 sharesClaimed,, uint256 assetsReceived) = arm.claimBaseAssetRedeem(address(token), AMOUNT);
        _assertTotalAssetsNeverDecreases(floor_);

        assertEq(sharesClaimed, AMOUNT, "sharesClaimed");
        assertEq(assetsReceived, AMOUNT, "assetsReceived");
        assertEq(usdc.balanceOf(address(arm)), armUsdcBefore + AMOUNT, "USDC back in the ARM");
        assertEq(adapter.pendingShares(), 0, "nothing pending");
        assertEq(adapter.settlingShares(), 0, "nothing settling");
        assertEq(_pendingRedeemAssets(token), 0, "queue fully claimed");
    }

    /// @dev Allows 1 wei of headroom for the split floor divisions in the cross-price valuation.
    function _assertTotalAssetsNeverDecreases(uint256 floor_) internal view returns (uint256 next) {
        next = arm.totalAssets();
        assertGe(next + 1, floor_, "totalAssets never decreases");
    }
}
