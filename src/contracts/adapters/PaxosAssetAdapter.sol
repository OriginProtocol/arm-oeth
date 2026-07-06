// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IAssetAdapter, IERC20} from "../Interfaces.sol";
import {OwnableOperable} from "../OwnableOperable.sol";

/**
 * @title Paxos asset adapter
 * @notice Adapter for redeeming Paxos-issued stablecoins through off-chain Paxos Actions with on-chain settlement.
 * @author Origin Protocol Inc
 */
contract PaxosAssetAdapter is Initializable, IAssetAdapter, OwnableOperable {
    /// @notice ARM contract authorized to request and claim redemptions.
    address public immutable arm;
    /// @notice Paxos-issued stablecoin supplied by the ARM.
    IERC20 public immutable baseAsset;
    /// @notice Liquidity stablecoin received after Paxos settlement.
    IERC20 public immutable liquidityAsset;

    /// @notice On-chain Paxos deposit address used by Actions to settle queued redemptions.
    address public paxosRecipient;
    /// @notice Base asset amount queued in the adapter but not yet sent to Paxos.
    uint256 public pendingShares;
    /// @notice Base asset amount sent to Paxos and awaiting on-chain USDC settlement.
    uint256 public settlingShares;

    error InvalidPaxosRecipient(); // 0xfd956f0b
    error PaxosRecipientNotConfigured(); // 0x11f03d8a
    error RedeemAmountTooHigh(); // 0xc4526429
    error InsufficientSettledAssets(uint256 required, uint256 available); // 0x34b0f470

    event PaxosRecipientUpdated(address indexed paxosRecipient);
    event PaxosRedeemSubmitted(bytes32 indexed paxosRedemptionId, uint256 shares, address indexed paxosRecipient);
    event ExcessLiquidityRecovered(address indexed to, uint256 amount);

    modifier onlyARM() {
        require(msg.sender == arm, "Adapter: only ARM");
        _;
    }

    modifier nonZeroShares(uint256 shares) {
        require(shares > 0, "Adapter: zero shares");
        _;
    }

    /// @param _arm ARM contract authorized to use the adapter.
    /// @param _baseAsset Paxos-issued stablecoin to redeem.
    /// @param _liquidityAsset Liquidity stablecoin received after Paxos settlement.
    constructor(address _arm, address _baseAsset, address _liquidityAsset) {
        arm = _arm;
        baseAsset = IERC20(_baseAsset);
        liquidityAsset = IERC20(_liquidityAsset);

        require(baseAsset.decimals() == liquidityAsset.decimals(), "Adapter: decimals mismatch");

        _setOwner(address(0));
        _disableInitializers();
    }

    /// @notice Initialize the adapter operator and optional Paxos recipient.
    /// @param _operator Account that can submit queued redemptions to Paxos.
    /// @param _paxosRecipient Paxos on-chain deposit address. `address(0)` leaves submission disabled.
    function initialize(address _operator, address _paxosRecipient) external initializer {
        _initOwnableOperable(_operator);
        if (_paxosRecipient != address(0)) _setPaxosRecipient(_paxosRecipient);
    }

    /// @notice Set the Paxos on-chain deposit address used for future submissions.
    /// @param _paxosRecipient Paxos deposit address for the adapter's base asset.
    function setPaxosRecipient(address _paxosRecipient) external onlyOwner {
        if (_paxosRecipient == address(0)) revert InvalidPaxosRecipient();
        _setPaxosRecipient(_paxosRecipient);
    }

    /// @notice Submit queued base assets to Paxos for API-orchestrated redemption.
    /// @dev Paxos Actions should use `paxosRedemptionId` to correlate this transfer with off-chain orchestration.
    /// @param shares Base asset amount to send. For example, `100e6` is 100 USDG/PYUSD.
    /// @param paxosRedemptionId Off-chain Paxos orchestration or idempotency identifier.
    function submitPaxosRedeem(uint256 shares, bytes32 paxosRedemptionId)
        external
        onlyOperatorOrOwner
        nonZeroShares(shares)
    {
        uint256 pendingSharesMem = pendingShares;
        if (shares > pendingSharesMem) revert RedeemAmountTooHigh();

        address paxosRecipientMem = paxosRecipient;
        if (paxosRecipientMem == address(0)) revert PaxosRecipientNotConfigured();

        pendingShares = pendingSharesMem - shares;
        settlingShares += shares;
        baseAsset.transfer(paxosRecipientMem, shares);

        emit PaxosRedeemSubmitted(paxosRedemptionId, shares, paxosRecipientMem);
    }

    /// @notice Returns the liquidity asset produced by Paxos settlement.
    function asset() external view returns (address) {
        return address(liquidityAsset);
    }

    /// @notice Converts base stablecoin shares into expected liquidity assets at 1:1.
    /// @param shares Base asset amount.
    /// @return assets Expected liquidity asset amount.
    function convertToAssets(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    /// @notice Converts liquidity assets into expected base stablecoin shares at 1:1.
    /// @param assets Liquidity asset amount.
    /// @return shares Expected base asset amount.
    function convertToShares(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    /// @notice Pulls base assets from the ARM and queues them for Paxos redemption.
    /// @param shares Base asset amount to queue.
    /// @return sharesRequested Base asset amount queued.
    /// @return assetsExpected Expected USDC from Paxos settlement.
    function requestRedeem(uint256 shares)
        external
        onlyARM
        nonZeroShares(shares)
        returns (uint256 sharesRequested, uint256 assetsExpected)
    {
        pendingShares += shares;
        baseAsset.transferFrom(arm, address(this), shares);

        sharesRequested = shares;
        assetsExpected = shares;
    }

    /// @notice Claims settled USDC after Paxos Actions complete on-chain settlement to this adapter.
    /// @param shares Base asset amount represented by the settled redemption.
    /// @return sharesClaimed Base asset amount claimed.
    /// @return assetsExpected Expected USDC from Paxos settlement.
    /// @return assetsReceived USDC transferred to the ARM.
    function redeem(uint256 shares)
        external
        onlyARM
        nonZeroShares(shares)
        returns (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived)
    {
        uint256 settlingSharesMem = settlingShares;
        if (shares > settlingSharesMem) revert RedeemAmountTooHigh();

        uint256 available = liquidityAsset.balanceOf(address(this));
        if (available < shares) revert InsufficientSettledAssets(shares, available);

        settlingShares = settlingSharesMem - shares;
        liquidityAsset.transfer(arm, shares);

        sharesClaimed = shares;
        assetsExpected = shares;
        assetsReceived = shares;
    }

    /// @notice Recovers liquidity asset held beyond what `settlingShares` still owes, e.g. donated tokens
    ///         or a Paxos settlement that arrived after its `settlingShares` was already closed out.
    /// @param to Recipient of the recovered liquidity asset.
    function recoverExcessLiquidity(address to) external onlyOwner {
        require(to != address(0), "Adapter: zero address");

        uint256 balance = liquidityAsset.balanceOf(address(this));
        uint256 settlingSharesMem = settlingShares;
        uint256 excess = balance > settlingSharesMem ? balance - settlingSharesMem : 0;

        liquidityAsset.transfer(to, excess);

        emit ExcessLiquidityRecovered(to, excess);
    }

    function _setPaxosRecipient(address _paxosRecipient) internal {
        paxosRecipient = _paxosRecipient;

        emit PaxosRecipientUpdated(_paxosRecipient);
    }
}
