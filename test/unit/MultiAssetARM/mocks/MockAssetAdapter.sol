// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAssetAdapter, IERC20} from "contracts/Interfaces.sol";

/// @notice Generic, protocol-agnostic test double for `IAssetAdapter`. It converts a base asset into the
///         ARM's liquidity asset across the supported {6, 18} decimal combinations, mirroring the exact 1e12
///         scaling used inside `AbstractARM._scaleBaseToLiquidity` / `_scaleLiquidityToBase` so that the ARM's
///         valuation (`totalAssets`) and swap math stay consistent with non-pegged base assets.
///
/// @dev A configurable `rate` (liquidity value per base unit, 1e18-scaled, default 1:1) emulates a
///      yield-bearing base. A configurable `shortfallBps` lets tests deliver less liquidity than expected on
///      claim, exercising the ARM's loss path. The adapter must be pre-funded with the liquidity asset.
contract MockAssetAdapter is IAssetAdapter {
    uint256 internal constant SCALE = 1e12;
    uint256 internal constant RATE_SCALE = 1e18;
    uint256 internal constant BPS = 10_000;

    /// @notice ARM contract authorized to request and claim redemptions.
    address public immutable arm;
    /// @notice Base asset pulled from the ARM on request.
    IERC20 public immutable baseAsset;
    /// @notice Liquidity asset returned to the ARM on claim.
    IERC20 public immutable liquidityAsset;
    /// @notice Decimals of the base asset (6 or 18).
    uint8 public immutable baseDecimals;
    /// @notice Decimals of the liquidity asset (6 or 18).
    uint8 public immutable liquidityDecimals;

    /// @notice Liquidity value per base unit, scaled to 1e18. 1e18 = 1:1 value.
    uint256 public rate = RATE_SCALE;
    /// @notice Reduction (in bps) applied to the delivered liquidity on claim, to emulate a protocol loss.
    uint256 public shortfallBps;

    /// @notice Base shares represented by each request id.
    mapping(uint256 requestId => uint256 shares) public requestShares;
    /// @notice Expected liquidity assets represented by each request id.
    mapping(uint256 requestId => uint256 assets) public requestAssets;
    uint256[] internal pendingRequestIds;
    uint256 internal nextPendingIndex;

    modifier onlyARM() {
        require(msg.sender == arm, "Adapter: only ARM");
        _;
    }

    constructor(address _arm, address _baseAsset, address _liquidityAsset) {
        arm = _arm;
        baseAsset = IERC20(_baseAsset);
        liquidityAsset = IERC20(_liquidityAsset);
        baseDecimals = IERC20(_baseAsset).decimals();
        liquidityDecimals = IERC20(_liquidityAsset).decimals();
    }

    /// @notice Test helper: set the liquidity-per-base value (1e18 = 1:1).
    function setRate(uint256 _rate) external {
        rate = _rate;
    }

    /// @notice Test helper: set the claim shortfall in bps (e.g. 100 = deliver 99% of expected).
    function setShortfallBps(uint256 _bps) external {
        shortfallBps = _bps;
    }

    function asset() external view returns (address) {
        return address(liquidityAsset);
    }

    /// @notice Convert base shares (native base decimals) to liquidity assets (native liquidity decimals).
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        return _scaleBaseToLiquidity(shares) * rate / RATE_SCALE;
    }

    /// @notice Convert liquidity assets (native liquidity decimals) to base shares (native base decimals).
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        return _scaleLiquidityToBase(assets) * RATE_SCALE / rate;
    }

    /// @notice Pull base shares from the ARM and queue a redemption request.
    function requestRedeem(uint256 shares) external onlyARM returns (uint256 sharesRequested, uint256 assetsExpected) {
        baseAsset.transferFrom(arm, address(this), shares);
        assetsExpected = convertToAssets(shares);

        uint256 requestId = pendingRequestIds.length;
        requestShares[requestId] = shares;
        requestAssets[requestId] = assetsExpected;
        pendingRequestIds.push(requestId);

        sharesRequested = shares;
    }

    /// @notice Claim queued requests in FIFO order and transfer the (possibly reduced) liquidity to the ARM.
    function redeem(uint256 shares)
        external
        onlyARM
        returns (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived)
    {
        uint256 length = pendingRequestIds.length;
        uint256 cursor = nextPendingIndex;
        uint256 claimCount;

        while (cursor + claimCount < length && sharesClaimed < shares) {
            uint256 requestId = pendingRequestIds[cursor + claimCount];
            uint256 requestShareAmount = requestShares[requestId];
            require(requestShareAmount > 0, "Adapter: invalid request");
            require(sharesClaimed + requestShareAmount <= shares, "Adapter: invalid redeem amount");

            sharesClaimed += requestShareAmount;
            assetsExpected += requestAssets[requestId];
            claimCount++;
        }

        require(sharesClaimed == shares, "Adapter: redeem exceeds claimable");

        for (uint256 i = 0; i < claimCount; ++i) {
            uint256 requestId = pendingRequestIds[cursor + i];
            delete requestShares[requestId];
            delete requestAssets[requestId];
        }
        nextPendingIndex = cursor + claimCount;

        // Deliver the expected liquidity minus any configured shortfall (emulates a protocol loss).
        assetsReceived = assetsExpected - (assetsExpected * shortfallBps / BPS);
        liquidityAsset.transfer(arm, assetsReceived);
    }

    /// @notice Total number of request ids ever stored.
    function pendingRequestIdsLength() external view returns (uint256) {
        return pendingRequestIds.length;
    }

    /// @notice Request id stored at `index`.
    function pendingRequestId(uint256 index) external view returns (uint256) {
        return pendingRequestIds[index];
    }

    /// @dev Mirror of AbstractARM._scaleBaseToLiquidity: base-native -> liquidity-native decimals.
    function _scaleBaseToLiquidity(uint256 amount) internal view returns (uint256) {
        if (baseDecimals == liquidityDecimals) return amount;
        return liquidityDecimals > baseDecimals ? amount * SCALE : amount / SCALE;
    }

    /// @dev Mirror of AbstractARM._scaleLiquidityToBase: liquidity-native -> base-native decimals.
    function _scaleLiquidityToBase(uint256 amount) internal view returns (uint256) {
        if (baseDecimals == liquidityDecimals) return amount;
        return baseDecimals > liquidityDecimals ? amount * SCALE : amount / SCALE;
    }
}
