// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IAssetAdapter, IERC20, IOwnable, IStETHWithdrawal, ISTETH, IWETH} from "../Interfaces.sol";

/**
 * @title Shared Lido withdrawal queue asset adapter
 * @notice Shared adapter logic for Lido withdrawal queue redemptions into WETH.
 * @dev Concrete implementations define how their share asset is converted into stETH before requesting withdrawals.
 * @author Origin Protocol Inc
 */
abstract contract AbstractLidoAssetAdapter is Initializable, IAssetAdapter {
    /// @notice Thrown when attempting to rescue an active adapter-managed withdrawal NFT.
    /// @param requestId Lido withdrawal NFT token id.
    error ActiveWithdrawalNFT(uint256 requestId);
    /// @notice Thrown when a caller other than the ARM owner attempts an owner-only action.
    error OnlyARMOwner();

    /// @notice Maximum stETH amount accepted by Lido for a single withdrawal request.
    uint256 internal constant MAX_WITHDRAWAL_AMOUNT = 1000 ether;

    /// @notice ARM contract authorized to request and claim redemptions.
    address public immutable arm;
    /// @notice WETH liquidity asset returned to the ARM.
    IWETH public immutable weth;
    /// @notice stETH token submitted to Lido's withdrawal queue.
    ISTETH public immutable steth;
    /// @notice Lido withdrawal queue used to request ETH redemptions.
    IStETHWithdrawal public immutable lidoWithdrawalQueue;

    /// @notice Share amount represented by each Lido withdrawal request id.
    mapping(uint256 requestId => uint256 shares) public requestShares;
    /// @notice Expected WETH amount represented by each Lido withdrawal request id.
    mapping(uint256 requestId => uint256 assets) public requestAssets;

    uint256[] internal pendingRequestIds;
    uint256 internal nextPendingIndex;

    event WithdrawalNFTRescued(uint256 indexed requestId, address indexed to);

    modifier onlyARM() {
        require(msg.sender == arm, "Adapter: only ARM");
        _;
    }

    modifier onlyARMOwner() {
        if (msg.sender != IOwnable(arm).owner()) revert OnlyARMOwner();
        _;
    }

    modifier nonZeroShares(uint256 shares) {
        require(shares > 0, "Adapter: zero shares");
        _;
    }

    /// @param _arm ARM contract authorized to use the adapter.
    /// @param _weth WETH token received after claims.
    /// @param _steth stETH token submitted to the withdrawal queue.
    /// @param _lidoWithdrawalQueue Lido withdrawal queue contract.
    constructor(address _arm, address _weth, address _steth, address _lidoWithdrawalQueue) {
        arm = _arm;
        weth = IWETH(_weth);
        steth = ISTETH(_steth);
        lidoWithdrawalQueue = IStETHWithdrawal(_lidoWithdrawalQueue);
    }

    /// @notice Re-approves stETH for the withdrawal queue when called through a proxy.
    function initialize() external initializer {
        IERC20(address(steth)).approve(address(lidoWithdrawalQueue), type(uint256).max);
    }

    /// @notice Returns WETH as the liquidity asset produced by Lido claims.
    function asset() external view returns (address) {
        return address(weth);
    }

    /// @notice Requests Lido withdrawals for the supplied share amount.
    /// @dev The stETH amount is split into chunks no larger than `MAX_WITHDRAWAL_AMOUNT` before calling Lido.
    /// @param shares Amount of concrete adapter shares to redeem.
    /// @return sharesRequested Amount of shares accepted into Lido withdrawal requests.
    /// @return assetsExpected Expected WETH amount based on stETH submitted.
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

    /// @notice Claims finalized Lido withdrawal requests and transfers WETH to the ARM.
    /// @dev Claims finalized pending requests in FIFO order and wraps any received ETH into WETH.
    /// @param shares Exact amount of shares represented by finalized pending requests to claim.
    /// @return sharesClaimed Amount of shares represented by claimed requests.
    /// @return assetsExpected Expected WETH amount recorded when requests were opened.
    /// @return assetsReceived Actual WETH amount received and transferred to the ARM.
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

    /// @notice Returns the FIFO prefix of pending Lido requests that is currently finalized and claimable.
    /// @return claimableShares Shares represented by the currently claimable request prefix.
    /// @return claimableAssets Expected WETH represented by the currently claimable request prefix.
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

    /// @notice Returns the total number of Lido request ids ever stored by the adapter.
    function pendingRequestIdsLength() external view returns (uint256) {
        return pendingRequestIds.length;
    }

    /// @notice Returns a stored Lido request id by array index.
    /// @param index Index in the pending request id array.
    function pendingRequestId(uint256 index) external view returns (uint256) {
        return pendingRequestIds[index];
    }

    /// @notice Rescue a Lido withdrawal NFT that was sent here by mistake.
    /// @dev Reverts for active adapter-managed withdrawal NFTs so legitimate requests cannot be rescued.
    /// @param requestId Lido withdrawal NFT token id.
    /// @param to Recipient of the rescued withdrawal NFT.
    function rescueWithdrawalNFT(uint256 requestId, address to) external onlyARMOwner {
        if (requestShares[requestId] != 0 || requestAssets[requestId] != 0) revert ActiveWithdrawalNFT(requestId);

        IERC721(address(lidoWithdrawalQueue)).safeTransferFrom(address(this), to, requestId);

        emit WithdrawalNFTRescued(requestId, to);
    }

    /// @notice Splits an amount into chunks accepted by the Lido withdrawal queue.
    /// @param amount stETH amount to split.
    /// @return amounts Array of stETH withdrawal amounts, each at most `MAX_WITHDRAWAL_AMOUNT`.
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

    /// @notice Splits a share amount proportionally across withdrawal amount chunks.
    /// @param totalShares Total share amount being redeemed.
    /// @param amounts stETH chunks being requested from Lido.
    /// @param totalAssets Total stETH amount represented by `totalShares`.
    /// @return shareSplits Share amount assigned to each withdrawal chunk.
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

    /// @notice Pulls the concrete share asset from `owner` and converts it into stETH held by this adapter.
    /// @param owner Address to pull shares from.
    /// @param shares Amount of concrete share asset to pull.
    /// @return assetsOut stETH amount available for Lido withdrawal requests.
    function _pullSharesAndConvertToSteth(address owner, uint256 shares) internal virtual returns (uint256 assetsOut);

    /// @notice Converts stETH assets back to the concrete adapter share amount.
    /// @param assets stETH amount.
    /// @return sharesOut Concrete adapter share amount.
    function _assetsToShares(uint256 assets) internal view virtual returns (uint256 sharesOut);

    receive() external payable {}
}
