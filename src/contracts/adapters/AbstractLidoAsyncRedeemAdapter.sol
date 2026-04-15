// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {ILidoAsyncRedeemAdapter, IERC20, IStETHWithdrawal, ISTETH, IWETH} from "../Interfaces.sol";

interface IARMOperatorAccess {
    function owner() external view returns (address);
    function operator() external view returns (address);
}

/**
 * @title Abstract Lido async redeem adapter
 * @notice Vault-shaped adapter that redeems Lido staking assets into WETH through the withdrawal queue.
 */
abstract contract AbstractLidoAsyncRedeemAdapter is ILidoAsyncRedeemAdapter {
    uint256 internal constant MAX_WITHDRAWAL_AMOUNT = 1000 ether;

    address public immutable arm;
    IWETH public immutable weth;
    ISTETH public immutable steth;
    IStETHWithdrawal public immutable lidoWithdrawalQueue;

    uint256 internal queuedSteth;

    mapping(uint256 requestId => uint256 shares) internal requestShares;
    mapping(uint256 requestId => uint256 assets) public override requestAssets;

    uint256[] internal pendingRequestIds;
    uint256 internal nextPendingIndex;

    constructor(address _arm, address _weth, address _steth, address _lidoWithdrawalQueue) {
        arm = _arm;
        weth = IWETH(_weth);
        steth = ISTETH(_steth);
        lidoWithdrawalQueue = IStETHWithdrawal(_lidoWithdrawalQueue);

        IERC20(_steth).approve(_lidoWithdrawalQueue, type(uint256).max);
    }

    function asset() external view returns (address) {
        return address(weth);
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256 assetsOut);

    function convertToShares(uint256 assetsIn) public view virtual returns (uint256 sharesOut);

    function requestRedeem(uint256 shares) external returns (uint256 requestedShares) {
        requestWithdrawal(shares);
        requestedShares = shares;
    }

    function requestWithdrawal(uint256 shares) public returns (uint256 requestId) {
        _onlyARM();
        require(shares > 0, "Adapter: zero shares");

        uint256 assetsOut = _pullSharesAndConvertToSteth(arm, shares);
        uint256[] memory amounts = _splitAmounts(assetsOut);
        uint256[] memory shareSplits = _splitShares(shares, amounts, assetsOut);
        uint256[] memory requestIds = lidoWithdrawalQueue.requestWithdrawals(amounts, address(this));

        uint256 totalAmounts;
        for (uint256 i = 0; i < requestIds.length; ++i) {
            requestShares[requestIds[i]] = shareSplits[i];
            requestAssets[requestIds[i]] = amounts[i];
            pendingRequestIds.push(requestIds[i]);
            totalAmounts += amounts[i];
        }

        queuedSteth += totalAmounts;
        requestId = requestIds[requestIds.length - 1];
    }

    function redeem(uint256 shares) external returns (uint256 assetsOut) {
        _onlyARM();

        (uint256[] memory requestIds, uint256[] memory hintIds, uint256 sharesClaimed,) = _claimableRequests(shares);
        require(sharesClaimed == shares, "Adapter: redeem exceeds claimable");
        (assetsOut,) = _claimRequests(requestIds, hintIds, msg.sender);
    }

    function claimWithdrawal(uint256[] calldata requestIds, uint256[] calldata hintIds)
        external
        returns (uint256 assetsOut, uint256 sharesClaimed)
    {
        _onlyARM();
        (assetsOut, sharesClaimed) = _claimRequests(requestIds, hintIds, arm);
    }

    function claimableRedeem() external view returns (uint256 claimableShares) {
        uint256 pendingCount = pendingRequestIds.length - nextPendingIndex;
        if (pendingCount == 0) return 0;

        uint256[] memory outstandingIds = new uint256[](pendingCount);
        for (uint256 i = 0; i < pendingCount; ++i) {
            outstandingIds[i] = pendingRequestIds[nextPendingIndex + i];
        }

        IStETHWithdrawal.WithdrawalRequestStatus[] memory statuses = lidoWithdrawalQueue.getWithdrawalStatus(outstandingIds);
        for (uint256 i = 0; i < statuses.length; ++i) {
            if (statuses[i].owner != address(this) || statuses[i].isClaimed || !statuses[i].isFinalized) break;
            claimableShares += requestShares[outstandingIds[i]];
        }
    }

    function _claimableRequests(uint256 targetShares)
        internal
        view
        returns (uint256[] memory requestIds, uint256[] memory hintIds, uint256 sharesClaimed, uint256 assetsClaimed)
    {
        require(targetShares > 0, "Adapter: zero shares");

        uint256 pendingCount = pendingRequestIds.length - nextPendingIndex;
        require(pendingCount > 0, "Adapter: no pending requests");

        uint256[] memory outstandingIds = new uint256[](pendingCount);
        for (uint256 i = 0; i < pendingCount; ++i) {
            outstandingIds[i] = pendingRequestIds[nextPendingIndex + i];
        }

        IStETHWithdrawal.WithdrawalRequestStatus[] memory statuses = lidoWithdrawalQueue.getWithdrawalStatus(outstandingIds);

        uint256 claimCount;
        for (uint256 i = 0; i < statuses.length; ++i) {
            if (statuses[i].owner != address(this) || statuses[i].isClaimed || !statuses[i].isFinalized) break;

            uint256 shareAmount = requestShares[outstandingIds[i]];
            uint256 assetAmount = requestAssets[outstandingIds[i]];
            if (sharesClaimed + shareAmount > targetShares) revert("Adapter: invalid redeem amount");

            sharesClaimed += shareAmount;
            assetsClaimed += assetAmount;
            claimCount++;

            if (sharesClaimed == targetShares) break;
        }

        require(sharesClaimed == targetShares, "Adapter: redeem exceeds claimable");

        requestIds = new uint256[](claimCount);
        for (uint256 i = 0; i < claimCount; ++i) {
            requestIds[i] = outstandingIds[i];
        }

        uint256 lastCheckpointIndex = lidoWithdrawalQueue.getLastCheckpointIndex();
        hintIds = lidoWithdrawalQueue.findCheckpointHints(requestIds, 1, lastCheckpointIndex);
    }

    function _claimRequests(uint256[] memory requestIds, uint256[] memory hintIds, address receiver)
        internal
        returns (uint256 assetsOut, uint256 sharesClaimed)
    {
        require(requestIds.length == hintIds.length, "Adapter: invalid hints");

        uint256 assetsClaimed;
        for (uint256 i = 0; i < requestIds.length; ++i) {
            uint256 expectedRequestId = pendingRequestIds[nextPendingIndex + i];
            require(requestIds[i] == expectedRequestId, "Adapter: invalid request id");

            sharesClaimed += requestShares[requestIds[i]];
            assetsClaimed += requestAssets[requestIds[i]];

            delete requestShares[requestIds[i]];
            delete requestAssets[requestIds[i]];
        }

        nextPendingIndex += requestIds.length;
        queuedSteth -= assetsClaimed;

        uint256 wethBefore = weth.balanceOf(address(this));
        lidoWithdrawalQueue.claimWithdrawals(requestIds, hintIds);

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            weth.deposit{value: ethBalance}();
        }

        assetsOut = weth.balanceOf(address(this)) - wethBefore;
        IERC20(address(weth)).transfer(receiver, assetsOut);
    }

    function _splitAmounts(uint256 amount) internal pure returns (uint256[] memory amounts) {
        uint256 chunkCount = amount / MAX_WITHDRAWAL_AMOUNT;
        if (amount % MAX_WITHDRAWAL_AMOUNT != 0) {
            chunkCount++;
        }

        amounts = new uint256[](chunkCount);
        uint256 remaining = amount;
        for (uint256 i = 0; i < chunkCount; ++i) {
            uint256 chunk = remaining > MAX_WITHDRAWAL_AMOUNT ? MAX_WITHDRAWAL_AMOUNT : remaining;
            amounts[i] = chunk;
            remaining -= chunk;
        }
    }

    function _splitShares(uint256 totalShares, uint256[] memory amounts, uint256 totalAssets)
        internal
        view
        returns (uint256[] memory shareSplits)
    {
        shareSplits = new uint256[](amounts.length);

        uint256 remainingShares = totalShares;
        uint256 remainingAssets = totalAssets;
        for (uint256 i = 0; i < amounts.length; ++i) {
            if (i == amounts.length - 1) {
                shareSplits[i] = remainingShares;
                break;
            }

            uint256 splitShares = _stethToShares(amounts[i]);
            if (splitShares > remainingShares) {
                splitShares = remainingShares;
            }
            if (splitShares == 0) {
                splitShares = remainingShares * amounts[i] / remainingAssets;
            }

            shareSplits[i] = splitShares;
            remainingShares -= splitShares;
            remainingAssets -= amounts[i];
        }
    }

    function _onlyARM() internal view {
        require(_isAuthorizedCaller(), "Adapter: only ARM");
    }

    function _isAuthorizedCaller() internal view returns (bool) {
        if (msg.sender == arm) return true;

        IARMOperatorAccess armAccess = IARMOperatorAccess(arm);
        return msg.sender == armAccess.owner() || msg.sender == armAccess.operator();
    }

    function _pullSharesAndConvertToSteth(address owner, uint256 shares) internal virtual returns (uint256 assetsOut);

    function _stethToShares(uint256 stethAmount) internal view virtual returns (uint256 sharesOut);

    receive() external payable {}
}
