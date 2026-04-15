// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Base_Test_} from "test/Base.sol";
import {ILidoAsyncRedeemAdapter, IStETHWithdrawal} from "contracts/Interfaces.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

abstract contract Helpers is Base_Test_ {
    function adapterOf(address asset) public view returns (address adapter) {
        (, adapter,,,,) = lidoARM.baseAssetConfigs(asset);
    }

    function adapterQueuedAmount(address adapter) public view returns (uint256 amount) {
        uint256[] memory requestIds = IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL).getWithdrawalRequests(adapter);
        for (uint256 i = 0; i < requestIds.length; ++i) {
            amount += ILidoAsyncRedeemAdapter(adapter).requestAssets(requestIds[i]);
        }
    }

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

    function lidoQueueAmount() public view returns (uint256 amount) {
        address stethAdapter = adapterOf(address(steth));
        if (stethAdapter != address(0)) {
            amount += adapterQueuedAmount(stethAdapter);
        }
        address wstethAdapter = adapterOf(address(wsteth));
        if (wstethAdapter != address(0)) {
            amount += adapterQueuedAmount(wstethAdapter);
        }
    }

    function lidoWithdrawalRequestAmount(uint256 requestId) public view returns (uint256 amount) {
        address stethAdapter = adapterOf(address(steth));
        if (stethAdapter != address(0)) {
            amount = ILidoAsyncRedeemAdapter(stethAdapter).requestAssets(requestId);
        }
        address wstethAdapter = adapterOf(address(wsteth));
        if (amount == 0 && wstethAdapter != address(0)) {
            amount = ILidoAsyncRedeemAdapter(wstethAdapter).requestAssets(requestId);
        }
    }

    function requestStethWithdrawals(uint256[] memory amounts) public returns (uint256[] memory requestIds) {
        requestIds = new uint256[](amounts.length);
        ILidoAsyncRedeemAdapter adapter = ILidoAsyncRedeemAdapter(adapterOf(address(steth)));
        for (uint256 i = 0; i < amounts.length; ++i) {
            requestIds[i] = adapter.requestWithdrawal(amounts[i], address(lidoARM), address(lidoARM));
        }
    }

    function requestStethVaultRedeems(uint256[] memory amounts) public returns (uint256[] memory requestIds) {
        requestIds = new uint256[](amounts.length);
        uint256 nextRequestId = IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL).getLastRequestId() + 1;
        for (uint256 i = 0; i < amounts.length; ++i) {
            lidoARM.requestVaultRedeem(address(steth), amounts[i]);
            requestIds[i] = nextRequestId++;
        }
    }

    function claimStethWithdrawals(uint256[] memory requestIds, uint256[] memory hintIds)
        public
        returns (uint256 assetsOut, uint256 sharesClaimed)
    {
        (assetsOut, sharesClaimed) =
            ILidoAsyncRedeemAdapter(adapterOf(address(steth))).claimWithdrawal(
                requestIds, hintIds, address(lidoARM), address(lidoARM)
            );
    }

    function claimStethVaultRedeem(uint256 shares) public returns (uint256 assetsOut) {
        assetsOut = lidoARM.claimVaultRedeem(address(steth), shares);
    }
}
