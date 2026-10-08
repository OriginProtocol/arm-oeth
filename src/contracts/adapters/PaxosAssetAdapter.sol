// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.36;

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

    /// @notice On-chain Paxos USDC deposit address used by Actions to initiate base-asset mints.
    address public paxosMintRecipient;
    /// @notice USDC pulled from the ARM but not yet sent to Paxos for minting.
    uint256 public pendingMintAssets;
    /// @notice USDC sent to Paxos and awaiting base-asset mint settlement.
    uint256 public settlingMintAssets;

    error InvalidPaxosRecipient(); // 0xfd956f0b
    error PaxosRecipientNotConfigured(); // 0x11f03d8a
    error RedeemAmountTooHigh(); // 0xc4526429
    error InsufficientSettledAssets(uint256 required, uint256 available); // 0x34b0f470
    error OnlyARM(); // 0x1628bf2a
    error ZeroShares(); // 0x9811e0c7
    error ZeroAssets(); // 0x32d971dc
    error DecimalsMismatch(); // 0x5a8dbaed
    error MintAmountTooHigh(); // 0xc2f508f9
    error InsufficientMintedShares(uint256 required, uint256 available); // 0x39dddda7

    event PaxosRecipientUpdated(address indexed paxosRecipient);
    /// @notice Emitted when base assets are queued for redemption, where `100e6` is 100 tokens for 6-decimal assets.
    event PaxosRedeemRequested(uint256 shares, uint256 assetsExpected);
    event PaxosRedeemSubmitted(bytes32 indexed paxosRedemptionId, uint256 shares, address indexed paxosRecipient);
    /// @notice Emitted when settled liquidity assets are transferred to the ARM, where `100e6` is 100 USDC.
    event PaxosRedeemClaimed(uint256 shares, uint256 assetsExpected, uint256 assetsReceived);
    event ExcessLiquidityRecovered(address indexed to, uint256 amount);
    event PaxosMintRecipientUpdated(address indexed paxosMintRecipient);
    /// @notice Emitted when USDC is queued for minting, where `100e6` is 100 USDC.
    event PaxosMintRequested(uint256 assets, uint256 sharesExpected);
    event PaxosMintSubmitted(bytes32 indexed paxosMintId, uint256 assets, address indexed paxosMintRecipient);
    /// @notice Emitted when minted base shares are transferred to the ARM.
    event PaxosMintClaimed(uint256 shares, uint256 assetsExpected, uint256 sharesReceived);
    event ExcessBaseAssetRecovered(address indexed to, uint256 amount);

    modifier onlyARM() {
        if (msg.sender != arm) revert OnlyARM();
        _;
    }

    modifier nonZeroShares(uint256 shares) {
        if (shares == 0) revert ZeroShares();
        _;
    }

    /// @param _arm ARM contract authorized to use the adapter.
    /// @param _baseAsset Paxos-issued stablecoin to redeem.
    /// @param _liquidityAsset Liquidity stablecoin received after Paxos settlement.
    constructor(address _arm, address _baseAsset, address _liquidityAsset) {
        arm = _arm;
        baseAsset = IERC20(_baseAsset);
        liquidityAsset = IERC20(_liquidityAsset);

        if (baseAsset.decimals() != liquidityAsset.decimals()) revert DecimalsMismatch();

        _setOwner(address(0));
        _disableInitializers();
    }

    /// @notice Initialize the adapter operator and Paxos recipient.
    /// @param _operator Account that can submit queued redemptions to Paxos.
    /// @param _paxosRecipient Paxos on-chain deposit address. Must be non-zero, otherwise reverts.
    function initialize(address _operator, address _paxosRecipient) external initializer {
        _initOwnableOperable(_operator);
        _setPaxosRecipient(_paxosRecipient);
        _setPaxosMintRecipient(_paxosRecipient);
    }

    /// @notice Set the Paxos on-chain deposit address used for future submissions.
    /// @param _paxosRecipient Paxos deposit address for the adapter's base asset.
    function setPaxosRecipient(address _paxosRecipient) external onlyOwner {
        _setPaxosRecipient(_paxosRecipient);
    }

    /// @notice Set the Paxos USDC deposit address used for future base-asset mints.
    function setPaxosMintRecipient(address _paxosMintRecipient) external onlyOwner {
        _setPaxosMintRecipient(_paxosMintRecipient);
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

        emit PaxosRedeemRequested(sharesRequested, assetsExpected);
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

        uint256 liquidityBalance = liquidityAsset.balanceOf(address(this));
        uint256 pendingMintAssetsMem = pendingMintAssets;
        uint256 available = liquidityBalance > pendingMintAssetsMem ? liquidityBalance - pendingMintAssetsMem : 0;
        if (available < shares) revert InsufficientSettledAssets(shares, available);

        settlingShares = settlingSharesMem - shares;
        liquidityAsset.transfer(arm, shares);

        sharesClaimed = shares;
        assetsExpected = shares;
        assetsReceived = shares;

        emit PaxosRedeemClaimed(sharesClaimed, assetsExpected, assetsReceived);
    }

    /// @notice Pull USDC from the ARM and queue it for a Paxos base-asset mint.
    /// @param assets USDC amount to queue. For example, `100e6` is 100 USDC.
    function requestMint(uint256 assets) external onlyARM returns (uint256 assetsRequested, uint256 sharesExpected) {
        if (assets == 0) revert ZeroAssets();

        pendingMintAssets += assets;
        liquidityAsset.transferFrom(arm, address(this), assets);

        assetsRequested = assets;
        sharesExpected = assets;

        emit PaxosMintRequested(assetsRequested, sharesExpected);
    }

    /// @notice Submit queued USDC to Paxos for API-orchestrated base-asset minting.
    /// @param assets USDC amount to send. For example, `100e6` is 100 USDC.
    /// @param paxosMintId Off-chain Paxos orchestration or idempotency identifier.
    function submitPaxosMint(uint256 assets, bytes32 paxosMintId) external onlyOperatorOrOwner {
        if (assets == 0) revert ZeroAssets();

        uint256 pendingMintAssetsMem = pendingMintAssets;
        if (assets > pendingMintAssetsMem) revert MintAmountTooHigh();

        address paxosMintRecipientMem = paxosMintRecipient;
        if (paxosMintRecipientMem == address(0)) revert PaxosRecipientNotConfigured();

        pendingMintAssets = pendingMintAssetsMem - assets;
        settlingMintAssets += assets;
        liquidityAsset.transfer(paxosMintRecipientMem, assets);

        emit PaxosMintSubmitted(paxosMintId, assets, paxosMintRecipientMem);
    }

    /// @notice Claim base assets minted by Paxos and transfer them into the ARM's sell inventory.
    function claimMint(uint256 shares)
        external
        onlyARM
        nonZeroShares(shares)
        returns (uint256 sharesClaimed, uint256 assetsExpected, uint256 sharesReceived)
    {
        uint256 settlingMintAssetsMem = settlingMintAssets;
        if (shares > settlingMintAssetsMem) revert MintAmountTooHigh();

        uint256 baseBalance = baseAsset.balanceOf(address(this));
        uint256 pendingRedeemShares = pendingShares;
        uint256 available = baseBalance > pendingRedeemShares ? baseBalance - pendingRedeemShares : 0;
        if (available < shares) revert InsufficientMintedShares(shares, available);

        settlingMintAssets = settlingMintAssetsMem - shares;
        baseAsset.transfer(arm, shares);

        sharesClaimed = shares;
        assetsExpected = shares;
        sharesReceived = shares;

        emit PaxosMintClaimed(sharesClaimed, assetsExpected, sharesReceived);
    }

    /// @notice Recovers liquidity asset held beyond what `settlingShares` still owes, e.g. donated tokens
    ///         or a Paxos settlement that arrived after its `settlingShares` was already closed out.
    /// @dev The recovered liquidity asset is always sent to the ARM.
    function recoverExcessLiquidity() external onlyOwner {
        uint256 balance = liquidityAsset.balanceOf(address(this));
        uint256 reserved = settlingShares + pendingMintAssets;
        uint256 excess = balance > reserved ? balance - reserved : 0;

        liquidityAsset.transfer(arm, excess);

        emit ExcessLiquidityRecovered(arm, excess);
    }

    /// @notice Recover base assets held beyond queued redemptions and unsettled mint obligations.
    /// @dev The recovered base asset is always sent to the ARM.
    function recoverExcessBaseAsset() external onlyOwner {
        uint256 balance = baseAsset.balanceOf(address(this));
        uint256 reserved = pendingShares + settlingMintAssets;
        uint256 excess = balance > reserved ? balance - reserved : 0;

        baseAsset.transfer(arm, excess);

        emit ExcessBaseAssetRecovered(arm, excess);
    }

    function _setPaxosRecipient(address _paxosRecipient) internal {
        if (_paxosRecipient == address(0)) revert InvalidPaxosRecipient();
        paxosRecipient = _paxosRecipient;

        emit PaxosRecipientUpdated(_paxosRecipient);
    }

    function _setPaxosMintRecipient(address _paxosMintRecipient) internal {
        if (_paxosMintRecipient == address(0)) revert InvalidPaxosRecipient();
        paxosMintRecipient = _paxosMintRecipient;

        emit PaxosMintRecipientUpdated(_paxosMintRecipient);
    }
}
