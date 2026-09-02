// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Fork_Shared_Test} from "test/fork/PaxosARM/shared/Shared.sol";
import {PaxosAssetAdapter} from "contracts/adapters/PaxosAssetAdapter.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";
import {IERC20} from "contracts/Interfaces.sol";

/// @notice Fork tests for converting ARM USDC into Paxos-minted PYUSD/USDG inventory.
contract Fork_Concrete_PaxosARM_PaxosMint_Test_ is Fork_Shared_Test {
    uint256 public constant AMOUNT = 10_000e6;
    bytes32 public constant PAXOS_MINT_ID = bytes32("paxos-mint-id");

    function test_RequestAndClaimBaseAssetMint_RevertWhen_NotOperatorOrOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        arm.requestBaseAssetMint(address(pyusd), AMOUNT);

        vm.prank(address(0xBEEF));
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        arm.claimBaseAssetMint(address(pyusd), AMOUNT);
    }

    function test_RequestAndClaimBaseAssetMint_RevertWhen_UnsupportedAsset() public {
        vm.prank(operator);
        vm.expectRevert(AbstractARM.UnsupportedAsset.selector);
        arm.requestBaseAssetMint(address(badToken), AMOUNT);

        vm.prank(operator);
        vm.expectRevert(AbstractARM.UnsupportedAsset.selector);
        arm.claimBaseAssetMint(address(badToken), AMOUNT);
    }

    function test_RequestBaseAssetMint_MovesUsdcAndTracksExpectedShares() public {
        uint256 totalAssetsBefore = arm.totalAssets();
        uint256 armUsdcBefore = usdc.balanceOf(address(arm));

        vm.prank(operator);
        (uint256 assetsRequested, uint256 sharesExpected) = arm.requestBaseAssetMint(address(pyusd), AMOUNT);

        assertEq(assetsRequested, AMOUNT, "assetsRequested");
        assertEq(sharesExpected, AMOUNT, "sharesExpected");
        assertEq(usdc.balanceOf(address(arm)), armUsdcBefore - AMOUNT, "ARM USDC committed");
        assertEq(usdc.balanceOf(address(pyusdAdapter)), AMOUNT, "adapter USDC queued");
        assertEq(pyusdAdapter.pendingMintAssets(), AMOUNT, "adapter pending mint");
        assertEq(arm.pendingMintShares(address(pyusd)), AMOUNT, "ARM expected mint shares");

        // Committing USDC to inventory recognizes the configured cross-price discount immediately.
        uint256 expectedDiscount = AMOUNT - (AMOUNT * CROSS_PRICE / PRICE_SCALE);
        assertApproxEqAbs(arm.totalAssets(), totalAssetsBefore - expectedDiscount, 1, "mint valued at cross price");
    }

    function test_ClaimBaseAssetMint_AfterSettlement() public {
        vm.prank(operator);
        arm.requestBaseAssetMint(address(pyusd), AMOUNT);
        vm.prank(operator);
        pyusdAdapter.submitPaxosMint(AMOUNT, PAXOS_MINT_ID);

        _settleMint(pyusd, pyusdAdapter, AMOUNT);

        uint256 totalAssetsBefore = arm.totalAssets();
        uint256 armBaseBefore = pyusd.balanceOf(address(arm));

        vm.prank(operator);
        (uint256 sharesClaimed, uint256 assetsExpected, uint256 sharesReceived) =
            arm.claimBaseAssetMint(address(pyusd), AMOUNT);

        assertEq(sharesClaimed, AMOUNT, "sharesClaimed");
        assertEq(assetsExpected, AMOUNT, "assetsExpected");
        assertEq(sharesReceived, AMOUNT, "sharesReceived");
        assertEq(pyusd.balanceOf(address(arm)), armBaseBefore + AMOUNT, "minted PYUSD in ARM");
        assertEq(arm.pendingMintShares(address(pyusd)), 0, "ARM expected mint shares cleared");
        assertEq(pyusdAdapter.settlingMintAssets(), 0, "adapter mint settlement cleared");
        assertApproxEqAbs(arm.totalAssets(), totalAssetsBefore, 1, "claim is NAV neutral");
    }

    function test_ClaimBaseAssetMint_RevertWhen_MoreThanPending() public {
        vm.prank(operator);
        arm.requestBaseAssetMint(address(pyusd), AMOUNT);
        vm.prank(operator);
        pyusdAdapter.submitPaxosMint(AMOUNT, PAXOS_MINT_ID);
        _settleMint(pyusd, pyusdAdapter, AMOUNT);

        vm.prank(operator);
        vm.expectRevert(PaxosAssetAdapter.MintAmountTooHigh.selector);
        arm.claimBaseAssetMint(address(pyusd), AMOUNT + 1);

        assertEq(arm.pendingMintShares(address(pyusd)), AMOUNT, "ARM pending shares unchanged");
        assertEq(pyusdAdapter.settlingMintAssets(), AMOUNT, "settling shares unchanged");

        vm.prank(operator);
        arm.claimBaseAssetMint(address(pyusd), AMOUNT);
        assertEq(arm.pendingMintShares(address(pyusd)), 0, "ARM pending shares cleared");
        assertEq(pyusdAdapter.settlingMintAssets(), 0, "full pending amount remains claimable");
    }

    function test_MintThenSell_Pyusd() public {
        _mintThenSell(pyusd, pyusdAdapter);
    }

    function test_MintThenSell_Usdg() public {
        _mintThenSell(usdg, usdgAdapter);
    }

    function test_SimultaneousMintAndRedeem_BalancesRemainIsolated() public {
        vm.prank(operator);
        arm.requestBaseAssetMint(address(pyusd), AMOUNT);

        vm.prank(operator);
        arm.requestBaseAssetRedeem(address(pyusd), AMOUNT);

        // Pending mint USDC cannot satisfy a redemption claim.
        vm.prank(operator);
        pyusdAdapter.submitPaxosRedeem(AMOUNT, bytes32("redeem"));
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaxosAssetAdapter.InsufficientSettledAssets.selector, AMOUNT, 0));
        arm.claimBaseAssetRedeem(address(pyusd), AMOUNT);

        // Submit the mint. With redemption inventory sent away, no base shares are available until Paxos mints them.
        vm.prank(operator);
        pyusdAdapter.submitPaxosMint(AMOUNT, bytes32("mint"));
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaxosAssetAdapter.InsufficientMintedShares.selector, AMOUNT, 0));
        arm.claimBaseAssetMint(address(pyusd), AMOUNT);

        _settle(pyusdAdapter, AMOUNT);
        _settleMint(pyusd, pyusdAdapter, AMOUNT);

        vm.prank(operator);
        arm.claimBaseAssetRedeem(address(pyusd), AMOUNT);
        vm.prank(operator);
        arm.claimBaseAssetMint(address(pyusd), AMOUNT);

        assertEq(arm.pendingMintShares(address(pyusd)), 0, "ARM mint queue cleared");
        assertEq(pyusdAdapter.settlingMintAssets(), 0, "mint queue cleared");
        assertEq(_pendingRedeemAssets(pyusd), 0, "redeem queue cleared");
    }

    function test_RevertWhen_LoweringCrossPrice_WithPendingMintExposure() public {
        vm.prank(operator);
        arm.requestBaseAssetMint(address(pyusd), AMOUNT);

        vm.prank(governor);
        vm.expectRevert(AbstractARM.TooManyBaseAssets.selector);
        arm.setCrossPrice(address(pyusd), CROSS_PRICE - 1);
    }

    function _mintThenSell(IERC20 token, PaxosAssetAdapter adapter) internal {
        uint256 armBaseBefore = token.balanceOf(address(arm));

        vm.prank(operator);
        arm.requestBaseAssetMint(address(token), AMOUNT);
        vm.prank(operator);
        adapter.submitPaxosMint(AMOUNT, PAXOS_MINT_ID);
        _settleMint(token, adapter, AMOUNT);
        vm.prank(operator);
        arm.claimBaseAssetMint(address(token), AMOUNT);

        assertEq(token.balanceOf(address(arm)), armBaseBefore + AMOUNT, "mint inventory received");

        uint256 traderUsdcBefore = usdc.balanceOf(address(this));
        arm.swapExactTokensForTokens(usdc, token, AMOUNT, 0, address(this));

        assertEq(usdc.balanceOf(address(this)), traderUsdcBefore - AMOUNT, "trader paid USDC");
        assertEq(token.balanceOf(address(arm)), armBaseBefore, "mint inventory sold");
    }
}
