// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Base_Test_} from "test/Base.sol";
import {AbstractLidoAssetAdapter} from "contracts/adapters/AbstractLidoAssetAdapter.sol";

abstract contract Helpers is Base_Test_ {
    /// @notice Override `deal()` function to handle OETH and STETH special case.
    function deal(address token, address to, uint256 amount) internal override {
        // Handle OETH special case, as rebasing tokens are not supported by the VM.
        if (token == address(oeth)) {
            // Check than whale as enough OETH.
            require(oeth.balanceOf(oethWhale) >= amount, "Fork_Shared_Test_: Not enough OETH in WHALE_OETH");

            // Transfer OETH from WHALE_OETH to the user.
            vm.prank(oethWhale);
            oeth.transfer(to, amount);
        } else if (token == address(steth)) {
            // Check than whale as enough stETH. Whale is wsteth contract.
            require(steth.balanceOf(address(wsteth)) >= amount, "Fork_Shared_Test_: Not enough stETH in WHALE_stETH");

            if (amount == 0) {
                vm.startPrank(to);
                steth.transfer(address(0x1), steth.balanceOf(to));
                vm.stopPrank();
            } else {
                // Transfer stETH from WHALE_stETH to the user.
                vm.prank(address(wsteth));
                steth.transfer(to, amount);
            }
        } else {
            super.deal(token, to, amount);
        }
    }

    /// @notice Asserts the equality between value of `withdrawalQueueMetadata()` and the expected values.
    function assertEqQueueMetadata(uint256 expectedQueued, uint256 expectedClaimed, uint256 expectedNextIndex)
        public
        view
    {
        assertEq(lidoARM.withdrawsQueued(), expectedQueued, "metadata queued");
        assertEq(lidoARM.withdrawsClaimed(), expectedClaimed, "metadata claimed");
        assertEq(lidoARM.nextWithdrawalIndex(), expectedNextIndex, "metadata nextWithdrawalIndex");
    }

    /// @notice Asserts the equality between value of `withdrawalRequests()` and the expected values.
    function assertEqUserRequest(
        uint256 requestId,
        address withdrawer,
        bool claimed,
        uint256 claimTimestamp,
        uint256 assets,
        uint256 queued,
        uint256 shares
    ) public view {
        (
            address _withdrawer,
            bool _claimed,
            uint40 _claimTimestamp,
            uint128 _assets,
            uint128 _queued,
            uint128 _shares
        ) = lidoARM.withdrawalRequests(requestId);
        assertEq(_withdrawer, withdrawer, "Wrong withdrawer");
        assertEq(_claimed, claimed, "Wrong claimed");
        assertEq(_claimTimestamp, claimTimestamp, "Wrong claimTimestamp");
        assertEq(_assets, assets, "Wrong assets");
        assertEq(_queued, queued, "Wrong queued");
        assertEq(_shares, shares, "Wrong shares");
    }

    function _lidoWithdrawalQueueAmount() internal view returns (uint256 pendingRedeemAssets) {
        (,,,,, uint120 _pendingRedeemAssets,,) = lidoARM.baseAssetConfigs(address(steth));
        pendingRedeemAssets = _pendingRedeemAssets;
    }

    function _lidoBuyPrice() internal view returns (uint256 buyPrice) {
        (uint128 _buyPrice,,,,,,,) = lidoARM.baseAssetConfigs(address(steth));
        buyPrice = _buyPrice;
    }

    function _lidoSellPrice() internal view returns (uint256 sellPrice) {
        (, uint128 _sellPrice,,,,,,) = lidoARM.baseAssetConfigs(address(steth));
        sellPrice = _sellPrice;
    }

    function _requestLidoWithdrawals(uint256[] memory amounts) internal returns (uint256[] memory requestIds) {
        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length; ++i) {
            totalAmount += amounts[i];
        }

        if (totalAmount == 0) return new uint256[](0);

        uint256 previousLength = AbstractLidoAssetAdapter(payable(stethAdapter)).pendingRequestIdsLength();
        lidoARM.requestRedeem(address(steth), totalAmount);
        uint256 newLength = AbstractLidoAssetAdapter(payable(stethAdapter)).pendingRequestIdsLength();

        requestIds = new uint256[](newLength - previousLength);
        for (uint256 i = 0; i < requestIds.length; ++i) {
            requestIds[i] = AbstractLidoAssetAdapter(payable(stethAdapter)).pendingRequestId(previousLength + i);
        }
    }

    function _claimLidoWithdrawals(uint256[] memory requestIds) internal {
        if (requestIds.length == 0) return;

        uint256 shares;
        for (uint256 i = 0; i < requestIds.length; ++i) {
            shares += AbstractLidoAssetAdapter(payable(stethAdapter)).requestShares(requestIds[i]);
        }

        lidoARM.claimRedeem(address(steth), shares);
    }
}
