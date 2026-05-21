// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IAssetAdapter, IERC20, IStETHWithdrawal, ISTETH, IWETH} from "../Interfaces.sol";

abstract contract AbstractLidoAssetAdapter is Initializable, IAssetAdapter {
    uint256 internal constant MAX_WITHDRAWAL_AMOUNT = 1000 ether;

    address public immutable arm;
    IWETH public immutable weth;
    ISTETH public immutable steth;
    IStETHWithdrawal public immutable lidoWithdrawalQueue;

    mapping(uint256 requestId => uint256 shares) public requestShares;
    mapping(uint256 requestId => uint256 assets) public requestAssets;

    uint256[] internal pendingRequestIds;
    uint256 internal nextPendingIndex;

    constructor(address _arm, address _weth, address _steth, address _lidoWithdrawalQueue) {
        arm = _arm;
        weth = IWETH(_weth);
        steth = ISTETH(_steth);
        lidoWithdrawalQueue = IStETHWithdrawal(_lidoWithdrawalQueue);
    }

    function initialize() external initializer {
        IERC20(address(steth)).approve(address(lidoWithdrawalQueue), type(uint256).max);
    }

    function asset() external view returns (address) {
        return address(weth);
    }

    function requestRedeem(uint256 shares)
        external
        onlyARM
        nonZeroShares(shares)
        returns (uint256 sharesRequested, uint256 assetsExpected)
    {
        assetsExpected = _pullSharesAndConvertToSteth(arm, shares);
        uint256[] memory amounts = _splitAmounts(assetsExpected);
        uint256[] memory shareSplits = _splitShares(shares, amounts, assetsExpected);
        uint256[] memory requestIds = lidoWithdrawalQueue.requestWithdrawals(amounts, address(this));

        for (uint256 i = 0; i < requestIds.length; ++i) {
            requestShares[requestIds[i]] = shareSplits[i];
            requestAssets[requestIds[i]] = amounts[i];
            pendingRequestIds.push(requestIds[i]);
        }

        sharesRequested = shares;
    }

    function redeem(uint256 shares)
        external
        onlyARM
        nonZeroShares(shares)
        returns (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived)
    {
        uint256 pendingCount = pendingRequestIds.length - nextPendingIndex;
        require(pendingCount > 0, "Adapter: no pending requests");

        uint256[] memory outstandingIds = new uint256[](pendingCount);
        for (uint256 i = 0; i < pendingCount; ++i) {
            outstandingIds[i] = pendingRequestIds[nextPendingIndex + i];
        }

        IStETHWithdrawal.WithdrawalRequestStatus[] memory statuses =
            lidoWithdrawalQueue.getWithdrawalStatus(outstandingIds);

        uint256 claimCount;
        for (uint256 i = 0; i < statuses.length; ++i) {
            if (statuses[i].owner != address(this) || statuses[i].isClaimed || !statuses[i].isFinalized) break;

            uint256 requestId = outstandingIds[i];
            uint256 requestShareAmount = requestShares[requestId];
            if (sharesClaimed + requestShareAmount > shares) revert("Adapter: invalid redeem amount");

            sharesClaimed += requestShareAmount;
            assetsExpected += requestAssets[requestId];
            claimCount++;

            if (sharesClaimed == shares) break;
        }

        require(sharesClaimed == shares, "Adapter: redeem exceeds claimable");

        uint256[] memory requestIds = new uint256[](claimCount);
        for (uint256 i = 0; i < claimCount; ++i) {
            requestIds[i] = outstandingIds[i];
            delete requestShares[requestIds[i]];
            delete requestAssets[requestIds[i]];
        }
        nextPendingIndex += claimCount;

        uint256 lastCheckpointIndex = lidoWithdrawalQueue.getLastCheckpointIndex();
        uint256[] memory hintIds = lidoWithdrawalQueue.findCheckpointHints(requestIds, 1, lastCheckpointIndex);

        uint256 wethBefore = weth.balanceOf(address(this));
        lidoWithdrawalQueue.claimWithdrawals(requestIds, hintIds);

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            weth.deposit{value: ethBalance}();
        }

        assetsReceived = weth.balanceOf(address(this)) - wethBefore;
        IERC20(address(weth)).transfer(arm, assetsReceived);
    }

    function claimableRedeem() external view returns (uint256 claimableShares, uint256 claimableAssets) {
        uint256 pendingCount = pendingRequestIds.length - nextPendingIndex;
        if (pendingCount == 0) return (0, 0);

        uint256[] memory outstandingIds = new uint256[](pendingCount);
        for (uint256 i = 0; i < pendingCount; ++i) {
            outstandingIds[i] = pendingRequestIds[nextPendingIndex + i];
        }

        IStETHWithdrawal.WithdrawalRequestStatus[] memory statuses =
            lidoWithdrawalQueue.getWithdrawalStatus(outstandingIds);

        for (uint256 i = 0; i < statuses.length; ++i) {
            if (statuses[i].owner != address(this) || statuses[i].isClaimed || !statuses[i].isFinalized) break;

            uint256 requestId = outstandingIds[i];
            claimableShares += requestShares[requestId];
            claimableAssets += requestAssets[requestId];
        }
    }

    function pendingRequestIdsLength() external view returns (uint256) {
        return pendingRequestIds.length;
    }

    function pendingRequestId(uint256 index) external view returns (uint256) {
        return pendingRequestIds[index];
    }

    function _splitAmounts(uint256 amount) internal pure returns (uint256[] memory amounts) {
        uint256 chunkCount = amount / MAX_WITHDRAWAL_AMOUNT;
        if (amount % MAX_WITHDRAWAL_AMOUNT != 0) chunkCount++;

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

            uint256 splitShares = _assetsToShares(amounts[i]);
            if (splitShares > remainingShares) splitShares = remainingShares;
            if (splitShares == 0) splitShares = remainingShares * amounts[i] / remainingAssets;

            shareSplits[i] = splitShares;
            remainingShares -= splitShares;
            remainingAssets -= amounts[i];
        }
    }

    modifier onlyARM() {
        require(msg.sender == arm, "Adapter: only ARM");
        _;
    }

    modifier nonZeroShares(uint256 shares) {
        require(shares > 0, "Adapter: zero shares");
        _;
    }

    function _pullSharesAndConvertToSteth(address owner, uint256 shares) internal virtual returns (uint256 assetsOut);
    function _assetsToShares(uint256 assets) internal view virtual returns (uint256 sharesOut);

    receive() external payable {}
}
