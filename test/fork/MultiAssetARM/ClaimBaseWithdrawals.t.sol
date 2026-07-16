// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/MultiAssetARM/shared/Shared.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

/// @notice Fork tests for `claimBaseAssetRedeem` on the MultiAssetARM. Each test opens a real request,
///         finalizes it on the live protocol (Lido via the FINALIZE_ROLE, Ether.fi via the NFT admin),
///         then claims and checks WETH actually lands on the ARM.
contract Fork_Concrete_MultiAssetARM_ClaimBaseWithdrawals_Test_ is Fork_Shared_Test {
    uint256 public constant AMOUNT = 100 ether;
    /// @dev Payouts are within a hair of the recorded expectation; allow 0.1% for protocol rounding.
    uint256 internal constant PAYOUT_TOLERANCE = 1e15;

    //////////////////////////////////////////////////////
    /// --- HAPPY PATHS
    //////////////////////////////////////////////////////
    function test_ClaimBaseWithdrawals_stETH() public {
        _claimLido(steth);
    }

    function test_ClaimBaseWithdrawals_wstETH() public {
        _claimLido(wsteth);
    }

    function test_ClaimBaseWithdrawals_eETH() public {
        _claimEtherFi(eeth);
    }

    function test_ClaimBaseWithdrawals_weETH() public {
        _claimEtherFi(weeth);
    }

    //////////////////////////////////////////////////////
    /// --- REVERT TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_Claim_stETH_NotFinalized() public {
        vm.prank(operator);
        arm.requestBaseAssetRedeem(address(steth), AMOUNT);

        // The Lido request exists but is not finalized, so the FIFO prefix is empty.
        vm.prank(operator);
        vm.expectRevert("Adapter: redeem exceeds claimable");
        arm.claimBaseAssetRedeem(address(steth), AMOUNT);
    }

    function test_RevertWhen_Claim_NoPendingRequests() public {
        vm.prank(operator);
        vm.expectRevert("Adapter: no pending requests");
        arm.claimBaseAssetRedeem(address(steth), AMOUNT);
    }

    function test_RevertWhen_Claim_NotOperatorOrOwner() public {
        vm.expectRevert(bytes4(keccak256("OnlyOperatorOrOwner()")));
        arm.claimBaseAssetRedeem(address(steth), AMOUNT);
    }

    function test_RevertWhen_Claim_DirectAdapterCall_NotARM() public {
        vm.prank(operator);
        vm.expectRevert("Adapter: only ARM");
        stethAssetAdapter.redeem(AMOUNT);
    }

    //////////////////////////////////////////////////////
    /// --- SHARED CLAIM LOGIC
    //////////////////////////////////////////////////////
    function _claimLido(IERC20 token) internal {
        vm.prank(operator);
        (, uint256 assetsExpectedAtRequest) = arm.requestBaseAssetRedeem(address(token), AMOUNT);
        uint256 id0 = _queue(token).pendingRequestId(0);

        _finalizeLido();

        uint256 armWethBefore = weth.balanceOf(address(arm));

        vm.prank(operator);
        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) =
            arm.claimBaseAssetRedeem(address(token), AMOUNT);

        _assertClaim(token, id0, assetsExpectedAtRequest, sharesClaimed, assetsExpected, assetsReceived, armWethBefore);
    }

    function _claimEtherFi(IERC20 token) internal {
        vm.prank(operator);
        (, uint256 assetsExpectedAtRequest) = arm.requestBaseAssetRedeem(address(token), AMOUNT);
        uint256 id0 = _queue(token).pendingRequestId(0);

        _finalizeEtherFi(id0, assetsExpectedAtRequest);

        uint256 armWethBefore = weth.balanceOf(address(arm));

        vm.prank(operator);
        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) =
            arm.claimBaseAssetRedeem(address(token), AMOUNT);

        _assertClaim(token, id0, assetsExpectedAtRequest, sharesClaimed, assetsExpected, assetsReceived, armWethBefore);
    }

    function _assertClaim(
        IERC20 token,
        uint256 id0,
        uint256 assetsExpectedAtRequest,
        uint256 sharesClaimed,
        uint256 assetsExpected,
        uint256 assetsReceived,
        uint256 armWethBefore
    ) internal view {
        assertEq(sharesClaimed, AMOUNT, "sharesClaimed");
        assertEq(assetsExpected, assetsExpectedAtRequest, "assetsExpected matches request");
        assertApproxEqRel(assetsReceived, assetsExpectedAtRequest, PAYOUT_TOLERANCE, "assetsReceived ~ expected");
        assertEq(weth.balanceOf(address(arm)) - armWethBefore, assetsReceived, "ARM WETH += received");
        assertEq(_pendingRedeemAssets(token), 0, "pendingRedeemAssets cleared");
        assertEq(_queue(token).requestShares(id0), 0, "request cleared");
    }
}
