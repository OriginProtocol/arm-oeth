// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20, ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {AbstractARM} from "./AbstractARM.sol";

/**
 * @title Abstract support to an ARM for multiple Liquidity Providers (LP)
 * @author Origin Protocol Inc
 */
abstract contract MultiLP is AbstractARM, ERC20Upgradeable {
    /// @notice The delay before a withdrawal request can be claimed in seconds
    uint256 public constant CLAIM_DELAY = 10 minutes;
    /// @dev The amount of shares that are minted to a dead address on initalization
    uint256 internal constant MIN_TOTAL_SUPPLY = 1e12;
    /// @dev The address with no known private key that the initial shares are minted to
    address internal constant DEAD_ACCOUNT = 0x000000000000000000000000000000000000dEaD;

    /// @notice The address of the asset that is used to add and remove liquidity. eg WETH
    address internal immutable liquidityAsset;

    struct WithdrawalQueueMetadata {
        // cumulative total of all withdrawal requests included the ones that have already been claimed
        uint128 queued;
        // cumulative total of all the requests that can be claimed including the ones that have already been claimed
        uint128 claimable;
        // total of all the requests that have been claimed
        uint128 claimed;
        // index of the next withdrawal request starting at 0
        uint128 nextWithdrawalIndex;
    }

    /// @notice Global metadata for the withdrawal queue including:
    /// queued - cumulative total of all withdrawal requests included the ones that have already been claimed
    /// claimable - cumulative total of all the requests that can be claimed including the ones already claimed
    /// claimed - total of all the requests that have been claimed
    /// nextWithdrawalIndex - index of the next withdrawal request starting at 0
    // slither-disable-next-line uninitialized-state
    WithdrawalQueueMetadata public withdrawalQueueMetadata;

    struct WithdrawalRequest {
        address withdrawer;
        bool claimed;
        // When the withdrawal can be claimed
        uint40 claimTimestamp;
        // Amount of assets to withdraw
        uint128 assets;
        // cumulative total of all withdrawal requests including this one.
        // this request can be claimed when this queued amount is less than or equal to the queue's claimable amount.
        uint128 queued;
    }

    /// @notice Mapping of withdrawal request indices to the user withdrawal request data
    mapping(uint256 requestId => WithdrawalRequest) public withdrawalRequests;

    uint256[47] private _gap;

    event RedeemRequested(
        address indexed withdrawer, uint256 indexed requestId, uint256 assets, uint256 queued, uint256 claimTimestamp
    );
    event RedeemClaimed(address indexed withdrawer, uint256 indexed requestId, uint256 assets);

    constructor(address _liquidityAsset) {
        require(_liquidityAsset == address(token0) || _liquidityAsset == address(token1), "invalid liquidity asset");
        liquidityAsset = _liquidityAsset;
    }

    /// @dev called by the concrete contract's `initialize` function
    function _initMultiLP(string calldata _name, string calldata _symbol) internal {
        __ERC20_init(_name, _symbol);

        // Transfer a small bit of liquidity from the intializer to this contract
        IERC20(liquidityAsset).transferFrom(msg.sender, address(this), MIN_TOTAL_SUPPLY);

        // mint a small amount of shares to a dead account so the total supply can never be zero
        // This avoids donation attacks when there are no assets in the ARM contract
        _mint(DEAD_ACCOUNT, MIN_TOTAL_SUPPLY);
    }

    /// @notice Preview the amount of shares that would be minted for a given amount of assets
    /// @param assets The amount of liquidity assets to deposit
    /// @return shares The amount of shares that would be minted
    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        shares = convertToShares(assets);
    }

    /// @notice deposit liquidity assets in exchange for liquidity provider (LP) shares.
    /// The caller needs to have approved the contract to transfer the assets.
    /// @param assets The amount of liquidity assets to deposit
    /// @return shares The amount of shares that were minted
    function deposit(uint256 assets) external returns (uint256 shares) {
        _preDepositHook();

        shares = convertToShares(assets);

        // Transfer the liquidity asset from the sender to this contract
        IERC20(liquidityAsset).transferFrom(msg.sender, address(this), assets);

        // mint shares
        _mint(msg.sender, shares);

        // Add WETH to the withdrawal queue if the queue has a shortfall
        _addWithdrawalQueueLiquidity();

        _postDepositHook(assets);
    }

    function _preDepositHook() internal virtual;
    function _postDepositHook(uint256 assets) internal virtual;

    /// @notice Preview the amount of assets that would be received for burning a given amount of shares
    /// @param shares The amount of shares to burn
    /// @return assets The amount of liquidity assets that would be received
    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

    /// @notice Request to redeem liquidity provider shares for liquidity assets
    /// @param shares The amount of shares the redeemer wants to burn for liquidity assets
    /// @return requestId The index of the withdrawal request
    /// @return assets The amount of liquidity assets that will be claimable by the redeemer
    function requestRedeem(uint256 shares) external returns (uint256 requestId, uint256 assets) {
        _preWithdrawHook();

        // Calculate the amount of assets to transfer to the redeemer
        assets = convertToAssets(shares);

        requestId = withdrawalQueueMetadata.nextWithdrawalIndex;
        uint256 queued = withdrawalQueueMetadata.queued + assets;
        uint256 claimTimestamp = block.timestamp + CLAIM_DELAY;

        // Store the next withdrawal request
        withdrawalQueueMetadata.nextWithdrawalIndex = SafeCast.toUint128(requestId + 1);
        // Store the updated queued amount which reserves WETH in the withdrawal queue
        withdrawalQueueMetadata.queued = SafeCast.toUint128(queued);
        // Store requests
        withdrawalRequests[requestId] = WithdrawalRequest({
            withdrawer: msg.sender,
            claimed: false,
            claimTimestamp: uint40(claimTimestamp),
            assets: SafeCast.toUint128(assets),
            queued: SafeCast.toUint128(queued)
        });

        // burn redeemer's shares
        _burn(msg.sender, shares);

        _postWithdrawHook(assets);

        emit RedeemRequested(msg.sender, requestId, assets, queued, claimTimestamp);
    }

    function _preWithdrawHook() internal virtual;
    function _postWithdrawHook(uint256 assets) internal virtual;

    /// @notice Claim liquidity assets from a previous withdrawal request after the claim delay has passed
    /// @param requestId The index of the withdrawal request
    /// @return assets The amount of liquidity assets that were transferred to the redeemer
    function claimRedeem(uint256 requestId) external returns (uint256 assets) {
        // Update the ARM's withdrawal queue details
        _addWithdrawalQueueLiquidity();

        // Load the structs from storage into memory
        WithdrawalRequest memory request = withdrawalRequests[requestId];
        WithdrawalQueueMetadata memory queue = withdrawalQueueMetadata;

        require(request.claimTimestamp <= block.timestamp, "Claim delay not met");
        // If there isn't enough reserved liquidity in the queue to claim
        require(request.queued <= queue.claimable, "Queue pending liquidity");
        require(request.withdrawer == msg.sender, "Not requester");
        require(request.claimed == false, "Already claimed");

        // Store the request as claimed
        withdrawalRequests[requestId].claimed = true;
        // Store the updated claimed amount
        withdrawalQueueMetadata.claimed = queue.claimed + request.assets;

        assets = request.assets;

        emit RedeemClaimed(msg.sender, requestId, assets);

        // transfer the liquidity asset to the withdrawer
        IERC20(liquidityAsset).transfer(msg.sender, assets);
    }

    /// @dev Adds liquidity to the withdrawal queue if there is a funding shortfall.
    function _addWithdrawalQueueLiquidity() internal returns (uint256 addedClaimable) {
        WithdrawalQueueMetadata memory queue = withdrawalQueueMetadata;

        // Check if the claimable amount is less than the queued amount
        uint256 queueShortfall = queue.queued - queue.claimable;

        // No need to do anything is the withdrawal queue is full funded
        if (queueShortfall == 0) {
            return 0;
        }

        uint256 liquidityBalance = IERC20(liquidityAsset).balanceOf(address(this));

        // Of the claimable withdrawal requests, how much is unclaimed?
        // That is, the amount of the liquidity assets that is currently allocated for the withdrawal queue
        uint256 allocatedLiquidity = queue.claimable - queue.claimed;

        // If there is no unallocated liquidity assets then there is nothing to add to the queue
        if (liquidityBalance <= allocatedLiquidity) {
            return 0;
        }

        uint256 unallocatedLiquidity = liquidityBalance - allocatedLiquidity;

        // the new claimable amount is the smaller of the queue shortfall or unallocated weth
        addedClaimable = queueShortfall < unallocatedLiquidity ? queueShortfall : unallocatedLiquidity;
        uint256 newClaimable = queue.claimable + addedClaimable;

        // Store the new claimable amount back to storage
        withdrawalQueueMetadata.claimable = SafeCast.toUint128(newClaimable);
    }

    /// @notice The total amount of assets in the ARM and external withdrawal queue,
    /// less the liquidity assets reserved for the withdrawal queue
    function totalAssets() public view virtual returns (uint256 assets) {
        // Get the assets in the ARM and external withdrawal queue
        assets = token0.balanceOf(address(this)) + token1.balanceOf(address(this)) + _externalWithdrawQueue();

        WithdrawalQueueMetadata memory queue = withdrawalQueueMetadata;

        // If the ARM becomes insolvent enough that the total value in the ARM and external withdrawal queue
        // is less than the outstanding withdrawals.
        if (assets + queue.claimed < queue.queued) {
            return 0;
        }

        // Need to remove the liquidity assets that have been reserved for the withdrawal queue
        return assets + queue.claimed - queue.queued;
    }

    /// @notice Calculates the amount of shares for a given amount of liquidity assets
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        uint256 totalAssetsMem = totalAssets();
        shares = (totalAssetsMem == 0) ? assets : (assets * totalSupply()) / totalAssetsMem;
    }

    /// @notice Calculates the amount of liquidity assets for a given amount of shares
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = (shares * totalAssets()) / totalSupply();
    }

    /// @dev Hook for calculating the amount of assets in an external withdrawal queue like Lido or OETH
    /// This is not the ARM's withdrawal queue
    function _externalWithdrawQueue() internal view virtual returns (uint256 assets);
}
