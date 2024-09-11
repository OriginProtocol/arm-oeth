// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20, ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {AbstractARM} from "./AbstractARM.sol";

abstract contract MultiLP is AbstractARM, ERC20Upgradeable {
    uint256 public constant CLAIM_DELAY = 10 minutes;
    uint256 public constant MIN_TOTAL_SUPPLY = 1e12;
    address public constant DEAD_ACCOUNT = 0x000000000000000000000000000000000000dEaD;

    address internal immutable liquidityToken;

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
        uint40 timestamp; // timestamp of the withdrawal request
        // Amount of assets to withdraw
        uint128 assets;
        // cumulative total of all withdrawal requests including this one.
        // this request can be claimed when this queued amount is less than or equal to the queue's claimable amount.
        uint128 queued;
    }

    /// @notice Mapping of withdrawal request indices to the user withdrawal request data
    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;

    event RedeemRequested(address indexed withdrawer, uint256 indexed requestId, uint256 assets, uint256 queued);
    event RedeemClaimed(address indexed withdrawer, uint256 indexed requestId, uint256 assets);

    constructor(address _liquidityToken) {
        require(_liquidityToken == address(token0) || _liquidityToken == address(token1), "invalid liquidity token");
        liquidityToken = _liquidityToken;
    }

    function _initMultiLP(string calldata _name, string calldata _symbol) internal {
        __ERC20_init(_name, _symbol);

        // Transfer a small bit of liquidity from the intializer to this contract
        IERC20(liquidityToken).transferFrom(msg.sender, address(this), MIN_TOTAL_SUPPLY);

        // mint a small amount of shares to a dead account so the total supply can never be zero
        // This avoids donation attacks when there are no assets in the ARM contract
        _mint(DEAD_ACCOUNT, MIN_TOTAL_SUPPLY);
    }

    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        shares = convertToShares(assets);
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        _preDepositHook();

        shares = convertToShares(assets);

        // Transfer the liquidity token from the sender to this contract
        IERC20(liquidityToken).transferFrom(msg.sender, address(this), assets);

        // mint shares
        _mint(msg.sender, shares);

        _postDepositHook(assets);
    }

    function _preDepositHook() internal virtual;
    function _postDepositHook(uint256 assets) internal virtual;

    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

    /// @notice Request to redeem liquidity provider shares for liquidity assets
    /// @param shares The amount of shares the redeemer wants to burn for assets
    function requestRedeem(uint256 shares) external returns (uint256 requestId, uint256 assets) {
        _preWithdrawHook();

        // burn redeemer's shares
        _burn(msg.sender, shares);

        // Calculate the amount of assets to transfer to the redeemer
        assets = previewRedeem(shares);

        requestId = withdrawalQueueMetadata.nextWithdrawalIndex;
        uint256 queued = withdrawalQueueMetadata.queued + assets;

        // Store the next withdrawal request
        withdrawalQueueMetadata.nextWithdrawalIndex = SafeCast.toUint128(requestId + 1);
        // Store requests
        withdrawalRequests[requestId] = WithdrawalRequest({
            withdrawer: msg.sender,
            claimed: false,
            timestamp: uint40(block.timestamp),
            assets: SafeCast.toUint128(assets),
            queued: SafeCast.toUint128(queued)
        });

        _postWithdrawHook(assets);

        emit RedeemRequested(msg.sender, requestId, assets, queued);
    }

    function _preWithdrawHook() internal virtual;
    function _postWithdrawHook(uint256 assets) internal virtual;

    function claimRedeem(uint256 requestId) external returns (uint256 assets) {
        if (withdrawalRequests[requestId].queued > withdrawalQueueMetadata.claimable) {
            // Add any WETH from the Dripper to the withdrawal queue
            _addWithdrawalQueueLiquidity();
        }

        // Load the structs from storage into memory
        WithdrawalRequest memory request = withdrawalRequests[requestId];
        WithdrawalQueueMetadata memory queue = withdrawalQueueMetadata;

        require(request.timestamp + CLAIM_DELAY <= block.timestamp, "Claim delay not met");
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

        // transfer the liquidity token to the withdrawer
        IERC20(liquidityToken).transfer(msg.sender, assets);
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

        uint256 liquidityBalance = IERC20(liquidityToken).balanceOf(address(this));

        // Of the claimable withdrawal requests, how much is unclaimed?
        // That is, the amount of the liquidity token that is currently allocated for the withdrawal queue
        uint256 allocatedLiquidity = queue.claimable - queue.claimed;

        // If there is no unallocated liquidity token then there is nothing to add to the queue
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

    function totalAssets() public view virtual returns (uint256) {
        // valuing both assets 1:1
        return token0.balanceOf(address(this)) + token1.balanceOf(address(this)) + _assetsInWithdrawQueue();
    }

    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        uint256 _totalAssets = totalAssets();
        shares = (_totalAssets == 0) ? assets : (assets * totalSupply()) / _totalAssets;
    }

    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = (shares * totalAssets()) / totalSupply();
    }

    function _assetsInWithdrawQueue() internal view virtual returns (uint256);
}
