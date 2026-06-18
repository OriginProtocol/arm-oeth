// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IAssetAdapter, IERC20} from "../Interfaces.sol";
import {Ownable} from "../Ownable.sol";

interface IStableSwapRoute {
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes calldata routeData)
        external
        returns (uint256 amountOut);
}

/**
 * @title Stable swap asset adapter
 * @notice Adapter for redeeming a same-decimal stablecoin base asset into the ARM liquidity asset through
 * a governance-configured route wrapper.
 * @author Origin Protocol Inc
 */
contract StableSwapAssetAdapter is IAssetAdapter, Ownable {
    /// @notice Scale used for basis-point slippage values. 10,000 = 100%.
    uint256 public constant BPS_SCALE = 10000;

    /// @notice ARM contract authorized to request and claim redemptions.
    address public immutable arm;
    /// @notice Base stablecoin supplied by the ARM.
    IERC20 public immutable baseAsset;
    /// @notice Liquidity stablecoin received by the ARM.
    IERC20 public immutable liquidityAsset;

    /// @notice Allowlisted route wrapper called during redemption claims.
    address public swapTarget;
    /// @notice Opaque route configuration passed to `swapTarget`.
    bytes public routeData;
    /// @notice Maximum accepted swap slippage, in basis points.
    uint16 public maxSlippageBps;
    /// @notice Base asset amount queued for swap redemption.
    uint256 public pendingShares;

    error InvalidSwapTarget(); // 0x3e82d32a
    error InvalidMaxSlippage(); // 0x606ba49d
    error SwapRouteNotConfigured(); // 0x4d3daea5
    error InsufficientSwapOutput(); // 0x7716b743
    error RedeemAmountTooHigh(); // 0xc4526429

    event SwapRouteUpdated(address indexed swapTarget, uint256 maxSlippageBps, bytes routeData);

    modifier onlyARM() {
        require(msg.sender == arm, "Adapter: only ARM");
        _;
    }

    modifier nonZeroShares(uint256 shares) {
        require(shares > 0, "Adapter: zero shares");
        _;
    }

    /// @param _arm ARM contract authorized to use the adapter.
    /// @param _baseAsset Base stablecoin to redeem.
    /// @param _liquidityAsset Liquidity stablecoin received after swaps.
    constructor(address _arm, address _baseAsset, address _liquidityAsset) {
        arm = _arm;
        baseAsset = IERC20(_baseAsset);
        liquidityAsset = IERC20(_liquidityAsset);

        require(baseAsset.decimals() == liquidityAsset.decimals(), "Adapter: decimals mismatch");

        _setOwner(address(0));
    }

    /// @notice Set the route wrapper and route data used for future redemption claims.
    /// @param _swapTarget Allowlisted route wrapper that implements `IStableSwapRoute`.
    /// @param _routeData Opaque route configuration passed to `swapTarget`.
    /// @param _maxSlippageBps Maximum accepted swap slippage. 10,000 = 100%, 50 = 0.5%.
    function setSwapRoute(address _swapTarget, bytes calldata _routeData, uint256 _maxSlippageBps) external onlyOwner {
        if (_swapTarget == address(0)) revert InvalidSwapTarget();
        if (_maxSlippageBps > BPS_SCALE) revert InvalidMaxSlippage();

        swapTarget = _swapTarget;
        routeData = _routeData;
        maxSlippageBps = uint16(_maxSlippageBps);

        emit SwapRouteUpdated(_swapTarget, _maxSlippageBps, _routeData);
    }

    /// @notice Returns the liquidity asset produced by swap claims.
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

    /// @notice Pulls base assets from the ARM and queues them for a future swap into liquidity assets.
    /// @param shares Base asset amount to queue.
    /// @return sharesRequested Base asset amount queued.
    /// @return assetsExpected Expected liquidity assets from the queued swap.
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

    /// @notice Swaps queued base assets into liquidity assets and transfers received liquidity to the ARM.
    /// @param shares Exact queued base asset amount to swap.
    /// @return sharesClaimed Base asset amount swapped.
    /// @return assetsExpected Expected liquidity assets before slippage.
    /// @return assetsReceived Liquidity assets received and transferred to the ARM.
    function redeem(uint256 shares)
        external
        onlyARM
        nonZeroShares(shares)
        returns (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived)
    {
        uint256 pendingSharesMem = pendingShares;
        if (shares > pendingSharesMem) revert RedeemAmountTooHigh();

        address swapTargetMem = swapTarget;
        if (swapTargetMem == address(0)) revert SwapRouteNotConfigured();

        pendingShares = pendingSharesMem - shares;
        assetsExpected = shares;
        uint256 minAmountOut = shares * (BPS_SCALE - maxSlippageBps) / BPS_SCALE;

        uint256 liquidityBefore = liquidityAsset.balanceOf(address(this));
        baseAsset.approve(swapTargetMem, 0);
        baseAsset.approve(swapTargetMem, shares);
        IStableSwapRoute(swapTargetMem)
            .swap(address(baseAsset), address(liquidityAsset), shares, minAmountOut, routeData);
        baseAsset.approve(swapTargetMem, 0);

        assetsReceived = liquidityAsset.balanceOf(address(this)) - liquidityBefore;
        if (assetsReceived < minAmountOut) revert InsufficientSwapOutput();

        liquidityAsset.transfer(arm, assetsReceived);
        sharesClaimed = shares;
    }
}
