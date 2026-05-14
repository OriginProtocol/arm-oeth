// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {OwnableOperable} from "./OwnableOperable.sol";
import {IAssetAdapter, IERC20, ICapManager} from "./Interfaces.sol";

/**
 * @title Generic Automated Redemption Manager (ARM)
 * @notice Coordinates liquidity-provider shares, two-token swaps, active market allocation, and
 * protocol-specific redemption adapters for one liquidity asset and one or more supported base assets.
 * @dev Existing ARM proxies depend on the original storage prefix. New multi-base state is appended after
 * legacy single-base storage so Lido, EtherFi, Ethena, and Origin ARMs can share this implementation.
 * @author Origin Protocol Inc
 */
abstract contract AbstractARM is OwnableOperable, ERC20Upgradeable {
    ////////////////////////////////////////////////////
    ///                 Constants
    ////////////////////////////////////////////////////

    /// @notice Maximum amount the Owner can set the cross price below 1 scaled to 36 decimals.
    /// 20e32 is a 0.2% deviation, or 20 basis points.
    uint256 public constant MAX_CROSS_PRICE_DEVIATION = 20e32;
    /// @notice Scale used for prices.
    uint256 public constant PRICE_SCALE = 1e36;
    /// @notice The amount of shares minted to a dead address on initialization.
    uint256 internal constant MIN_TOTAL_SUPPLY = 1e12;
    /// @notice Address with no known private key that receives initial dead shares.
    address internal constant DEAD_ACCOUNT = 0x000000000000000000000000000000000000dEaD;
    /// @notice Scale of the swap fee. 10,000 = 100%.
    uint256 public constant FEE_SCALE = 10000;

    ////////////////////////////////////////////////////
    ///                 Immutables
    ////////////////////////////////////////////////////

    /// @notice The minimum amount of active market shares that can be redeemed during allocation.
    uint256 public immutable minSharesToRedeem;
    /// @notice Minimum excess liquidity delta before allocation will move funds to an active market.
    /// This should be close to zero.
    /// @dev Prevents allocation from repeatedly bouncing around a near-zero target delta.
    int256 public immutable allocateThreshold;
    /// @notice Asset used for LP deposits, LP redeem claims, and base-asset quote pricing.
    address public immutable liquidityAsset;
    /// @notice Delay before an LP redeem request can be claimed in seconds. eg 600 is 10 minutes.
    uint256 public immutable claimDelay;

    ////////////////////////////////////////////////////
    ///                 Storage
    ////////////////////////////////////////////////////

    /// @dev Legacy single-base storage. Keep this prefix unchanged for existing proxy upgrades.
    /// These fields are retained for storage/ABI compatibility and are not the source of truth for
    /// multi-base swap pricing.
    uint256 internal _deprecatedTraderate0;
    uint256 internal _deprecatedTraderate1;
    uint256 internal _deprecatedCrossPrice;

    /// @notice Maximum liquidity assets reserved for outstanding LP withdrawal requests.
    /// @dev Reuses the legacy packed `withdrawsQueued`/`withdrawsClaimed` storage slot.
    uint256 public reservedWithdrawLiquidity;
    /// @notice Index of the next LP withdrawal request.
    uint256 public nextWithdrawalIndex;

    /// @notice LP withdrawal request for liquidity assets.
    struct WithdrawalRequest {
        address withdrawer;
        bool claimed;
        /// @notice Timestamp after which the request can be claimed.
        uint40 claimTimestamp;
        /// @notice Liquidity assets requested at request time.
        uint128 assets;
        /// @notice Cumulative queued LP shares including this request.
        uint128 queued;
        /// @notice LP shares escrowed when this request was made.
        uint128 shares;
    }

    /// @notice Mapping of LP withdrawal request ids to request data.
    mapping(uint256 requestId => WithdrawalRequest) public withdrawalRequests;

    /// @notice Swap fee share collected on discounted base-asset buy swaps, in basis points.
    /// 10,000 = 100% fee
    /// 500 = 5% fee
    uint16 public fee;
    /// @dev Deprecated storage retained for layout compatibility.
    int128 internal _deprecatedLastAvailableAssets;
    /// @notice Account or contract that can collect accrued swap fees.
    address public feeCollector;
    /// @notice Optional CapManager contract used to enforce LP and total asset caps.
    address public capManager;

    /// @notice Active ERC-4626 lending market used for excess liquidity.
    address public activeMarket;
    /// @notice Lending markets that can be used by the ARM.
    mapping(address market => bool supported) public supportedMarkets;
    /// @notice Percentage of available liquid assets to keep in the ARM. 100% = 1e18.
    uint256 public armBuffer;
    /// @notice Accrued swap fees denominated in the liquidity asset.
    uint128 public feesAccrued;

    /// @notice Per-base-asset swap, valuation, and adapter configuration.
    /// @dev Packed into three storage slots. `adapter != address(0)` is the supported-asset flag.
    struct BaseAssetConfig {
        /// @notice Price the ARM pays in liquidity-asset terms when buying this base asset from traders.
        uint128 buyPrice;
        /// @notice Price the ARM charges in liquidity-asset terms when selling this base asset to traders.
        uint128 sellPrice;
        /// @notice Remaining liquidity asset the ARM can pay out at the current buy price.
        uint128 buyLiquidityRemaining;
        /// @notice Remaining base asset the ARM can sell at the current sell price.
        uint128 sellLiquidityRemaining;
        /// @notice Valuation price used by totalAssets(), scaled to 36 decimals.
        uint128 crossPrice;
        /// @notice Liquidity-denominated value expected from adapter redemption queues.
        uint120 pendingRedeemAssets;
        /// @notice If true, conversions bypass the adapter and use 1:1 amounts.
        bool peggedToLiquidityAsset;
        /// @notice Adapter that owns protocol-specific redemption logic for this base asset.
        address adapter;
    }

    /// @notice Supported base assets for totalAssets() iteration.
    address[] internal baseAssets;
    /// @notice Base asset configuration. A zero adapter means unsupported.
    mapping(address asset => BaseAssetConfig) public baseAssetConfigs;

    /// @notice Cumulative LP shares queued for redemption, used by the FIFO gate.
    uint128 public withdrawsQueuedShares;
    /// @notice Cumulative LP shares claimed and burned.
    uint128 public withdrawsClaimedShares;

    uint256[34] private _gap;

    ////////////////////////////////////////////////////
    ///                 Events
    ////////////////////////////////////////////////////

    event BaseAssetAdded(
        address indexed asset,
        address indexed adapter,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 crossPrice,
        bool peggedToLiquidityAsset
    );
    event TraderateChanged(address indexed asset, uint256 buyPrice, uint256 sellPrice);
    event CrossPriceUpdated(address indexed asset, uint256 crossPrice);
    event Deposit(address indexed owner, uint256 assets, uint256 shares);
    event RedeemRequested(
        address indexed withdrawer, uint256 indexed requestId, uint256 assets, uint256 queued, uint256 claimTimestamp
    );
    event RedeemClaimed(address indexed withdrawer, uint256 indexed requestId, uint256 assets);
    event FeeCollected(address indexed feeCollector, uint256 fee);
    event FeeUpdated(uint256 fee);
    event FeeCollectorUpdated(address indexed newFeeCollector);
    event CapManagerUpdated(address indexed capManager);
    event ActiveMarketUpdated(address indexed market);
    event MarketAdded(address indexed market);
    event MarketRemoved(address indexed market);
    event ARMBufferUpdated(uint256 armBuffer);
    event Allocated(address indexed market, int256 targetLiquidityDelta, int256 actualLiquidityDelta);

    ////////////////////////////////////////////////////
    ///                 Constructor
    ////////////////////////////////////////////////////

    /// @param _liquidityAsset Asset used for LP deposits/redeems and base-asset quote pricing.
    /// @param _claimDelay Delay in seconds before an LP redeem request can be claimed.
    /// eg 600 is 10 minutes.
    /// @param _minSharesToRedeem Minimum active market shares to redeem when pulling liquidity.
    /// @param _allocateThreshold Minimum excess liquidity delta before allocation deposits into a market.
    /// eg 1e18 is 1 liquidity asset.
    constructor(address _liquidityAsset, uint256 _claimDelay, uint256 _minSharesToRedeem, int256 _allocateThreshold) {
        require(IERC20(_liquidityAsset).decimals() == 18);
        require(_allocateThreshold >= 0, "invalid allocate threshold");

        liquidityAsset = _liquidityAsset;
        claimDelay = _claimDelay;
        minSharesToRedeem = _minSharesToRedeem;
        allocateThreshold = _allocateThreshold;

        // Revoke owner for implementation contract at deployment
        _setOwner(address(0));
    }

    ////////////////////////////////////////////////////
    ///                 Initializer
    ////////////////////////////////////////////////////

    /// @notice Initialize storage for the proxy.
    /// @dev The initializer caller must approve this ARM proxy to transfer `MIN_TOTAL_SUPPLY` liquidity assets.
    /// @param _operator Account allowed to run operator-only actions.
    /// @param _name LP token name.
    /// @param _symbol LP token symbol.
    /// @param _fee Fee on discounted base-asset buy swaps measured in basis points.
    /// 10,000 = 100% fee
    /// 500 = 5% fee
    /// @param _feeCollector Account or contract that receives accrued swap fees.
    /// @param _capManager Optional CapManager contract. Use address(0) to disable caps.
    function _initARM(
        address _operator,
        string calldata _name,
        string calldata _symbol,
        uint256 _fee,
        address _feeCollector,
        address _capManager
    ) internal {
        _initOwnableOperable(_operator);
        __ERC20_init(_name, _symbol);

        // Transfer a small bit of liquidity from the initializer to this contract.
        IERC20(liquidityAsset).transferFrom(msg.sender, address(this), MIN_TOTAL_SUPPLY);
        // Mint a small amount of shares to a dead account so total supply can never be zero.
        // This avoids donation attacks when there are no assets in the ARM contract.
        _mint(DEAD_ACCOUNT, MIN_TOTAL_SUPPLY);

        _setFee(_fee);
        _setFeeCollector(_feeCollector);

        capManager = _capManager;
        emit CapManagerUpdated(_capManager);
    }

    ////////////////////////////////////////////////////
    ///                 Swap Functions
    ////////////////////////////////////////////////////

    /// @notice Swap an exact amount of input tokens for as many output tokens as possible.
    /// @param inToken Token transferred from the caller.
    /// @param outToken Token transferred to `to`.
    /// @param amountIn Exact amount of `inToken` to swap.
    /// @param amountOutMin Minimum acceptable `outToken` amount.
    /// @param to Recipient of `outToken`.
    /// @return amounts Two-element array containing input and output amounts.
    function swapExactTokensForTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external virtual returns (uint256[] memory amounts) {
        uint256 amountOut = _swapExactTokensForTokens(inToken, outToken, amountIn, to);
        require(amountOut >= amountOutMin, "ARM: Insufficient output amount");

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    /// @notice Uniswap V2 Router compatible exact-input swap.
    /// @param amountIn Exact amount of path[0] to swap.
    /// @param amountOutMin Minimum acceptable path[1] amount.
    /// @param path Two-token path of input and output token addresses.
    /// @param to Recipient of output tokens.
    /// @param deadline Unix timestamp after which the swap reverts.
    /// @return amounts Two-element array containing input and output amounts.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual returns (uint256[] memory amounts) {
        require(path.length == 2, "ARM: Invalid path length");
        _inDeadline(deadline);

        uint256 amountOut = _swapExactTokensForTokens(IERC20(path[0]), IERC20(path[1]), amountIn, to);
        require(amountOut >= amountOutMin, "ARM: Insufficient output amount");

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    /// @notice Receive an exact amount of output tokens for as few input tokens as possible.
    /// @param inToken Token transferred from the caller.
    /// @param outToken Token transferred to `to`.
    /// @param amountOut Exact amount of `outToken` to receive.
    /// @param amountInMax Maximum acceptable `inToken` amount.
    /// @param to Recipient of `outToken`.
    /// @return amounts Two-element array containing input and output amounts.
    function swapTokensForExactTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountOut,
        uint256 amountInMax,
        address to
    ) external virtual returns (uint256[] memory amounts) {
        uint256 amountIn = _swapTokensForExactTokens(inToken, outToken, amountOut, to);
        require(amountIn <= amountInMax, "ARM: Excess input amount");

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    /// @notice Uniswap V2 Router compatible exact-output swap.
    /// @param amountOut Exact amount of path[1] to receive.
    /// @param amountInMax Maximum acceptable path[0] amount.
    /// @param path Two-token path of input and output token addresses.
    /// @param to Recipient of output tokens.
    /// @param deadline Unix timestamp after which the swap reverts.
    /// @return amounts Two-element array containing input and output amounts.
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual returns (uint256[] memory amounts) {
        require(path.length == 2, "ARM: Invalid path length");
        _inDeadline(deadline);

        uint256 amountIn = _swapTokensForExactTokens(IERC20(path[0]), IERC20(path[1]), amountOut, to);
        require(amountIn <= amountInMax, "ARM: Excess input amount");

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    /// @param deadline Unix timestamp that must not be in the past.
    function _inDeadline(uint256 deadline) internal view {
        require(deadline >= block.timestamp, "ARM: Deadline expired");
    }

    ////////////////////////////////////////////////////
    ///                 Swap Internals
    ////////////////////////////////////////////////////

    /// @dev Swap exact input between the liquidity asset and one supported base asset.
    /// @param inToken Token transferred from the caller.
    /// @param outToken Token transferred to `to`.
    /// @param amountIn Exact amount of `inToken` to swap.
    /// @param to Recipient of `outToken`.
    /// @return amountOut Amount of `outToken` transferred to `to`.
    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, address to)
        internal
        returns (uint256 amountOut)
    {
        (address swapBaseAsset, bool isBuySide) = _getSwapBaseAsset(address(inToken), address(outToken));
        BaseAssetConfig storage config = baseAssetConfigs[swapBaseAsset];

        if (!isBuySide) {
            // Trader sells liquidity asset and buys the base asset.
            // The ARM buys the liquidity asset and sells the base asset.
            // ARM prices the base sale at sellPrice.
            uint256 convertedAmountIn = _convertToShares(config, amountIn);
            // sellPrice is liquidity assets per base asset, so divide liquidity input by sellPrice
            // to get the base output owed to the trader.
            amountOut = convertedAmountIn * PRICE_SCALE / config.sellPrice;
        } else {
            // Trader sells base asset and buys the liquidity asset.
            // The ARM buys the base asset and sells the liquidity asset.
            // ARM prices the base purchase at buyPrice.
            uint256 convertedAmountIn = _convertToAssets(config, amountIn);
            // buyPrice is liquidity assets per base asset. Since convertedAmountIn is the
            // base input expressed in liquidity terms, multiply by buyPrice to get liquidity output.
            amountOut = convertedAmountIn * config.buyPrice / PRICE_SCALE;

            _accrueSwapFee(config.buyPrice, config.crossPrice, amountOut);
            _ensureLiquidityAvailableForSwap(amountOut);
        }

        _consumeSwapLiquidityLimit(config, isBuySide, amountOut);

        // Transfer the input tokens from the caller to this ARM contract
        inToken.transferFrom(msg.sender, address(this), amountIn);

        // Transfer the output tokens to the recipient
        outToken.transfer(to, amountOut);
    }

    /// @dev Swap for exact output between the liquidity asset and one supported base asset.
    /// @param inToken Token transferred from the caller.
    /// @param outToken Token transferred to `to`.
    /// @param amountOut Exact amount of `outToken` to receive.
    /// @param to Recipient of `outToken`.
    /// @return amountIn Amount of `inToken` transferred from the caller.
    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountOut, address to)
        internal
        returns (uint256 amountIn)
    {
        (address swapBaseAsset, bool isBuySide) = _getSwapBaseAsset(address(inToken), address(outToken));
        BaseAssetConfig storage config = baseAssetConfigs[swapBaseAsset];

        if (!isBuySide) {
            // Trader sells liquidity asset and buys the base asset.
            // The ARM buys the liquidity asset and sells the base asset.
            // ARM prices the base sale at sellPrice.
            uint256 convertedAmountOut = _convertToAssets(config, amountOut);
            // amountOut is converted to liquidity terms first, then multiplied by sellPrice
            // to solve for the required liquidity input.
            amountIn = convertedAmountOut * config.sellPrice / PRICE_SCALE + 3;
        } else {
            // Trader sells base asset and buys the liquidity asset.
            // The ARM buys the base asset and sells the liquidity asset.
            // ARM prices the base purchase at buyPrice.
            uint256 convertedAmountOut = _convertToShares(config, amountOut);
            // buyPrice is liquidity assets per base asset, but amountIn is base assets.
            // Divide the exact liquidity output by buyPrice to solve for the required base input.
            amountIn = convertedAmountOut * PRICE_SCALE / config.buyPrice + 3;

            _accrueSwapFee(config.buyPrice, config.crossPrice, amountOut);
            _ensureLiquidityAvailableForSwap(amountOut);
        }

        _consumeSwapLiquidityLimit(config, isBuySide, amountOut);

        // Transfer the input tokens from the caller to this ARM contract
        inToken.transferFrom(msg.sender, address(this), amountIn);

        // Transfer the output tokens to the recipient
        outToken.transfer(to, amountOut);
    }

    /// @dev Resolve the supported base asset from a 2-token swap pair.
    /// @param inToken Swap input token address.
    /// @param outToken Swap output token address.
    /// @return swapBaseAsset Supported base asset involved in the swap.
    /// @return isBuySide True when the ARM buys base asset and pays out liquidity asset.
    function _getSwapBaseAsset(address inToken, address outToken)
        internal
        view
        returns (address swapBaseAsset, bool isBuySide)
    {
        if (inToken == liquidityAsset && baseAssetConfigs[outToken].adapter != address(0)) {
            return (outToken, false);
        }
        if (outToken == liquidityAsset && baseAssetConfigs[inToken].adapter != address(0)) {
            return (inToken, true);
        }
        revert("ARM: Invalid swap assets");
    }

    /// @dev Ensure enough unreserved liquidity exists for a swap, withdrawing from the active market if needed.
    /// @param amount Liquidity asset amount needed by the swap.
    function _ensureLiquidityAvailableForSwap(uint256 amount) internal {
        uint256 liquidityBalance = IERC20(liquidityAsset).balanceOf(address(this));
        uint256 requiredLiquidity = amount + reservedWithdrawLiquidity;
        if (requiredLiquidity <= liquidityBalance) return;

        address activeMarketMem = activeMarket;
        require(activeMarketMem != address(0), "ARM: Insufficient liquidity");

        uint256 shortfall = requiredLiquidity - liquidityBalance;
        try IERC4626(activeMarketMem).withdraw(shortfall, address(this), address(this)) {}
        catch {
            revert("ARM: Insufficient liquidity");
        }
    }

    /// @dev Consume the per-base liquidity limit for the current swap direction.
    /// Buy-side limits are denominated in liquidity assets. Sell-side limits are denominated in base assets.
    /// @param config Base asset config whose liquidity limit is consumed.
    /// @param isBuySide True when the ARM buys base asset and pays out liquidity asset.
    /// @param amountOut Amount of output token sent by the ARM.
    function _consumeSwapLiquidityLimit(BaseAssetConfig storage config, bool isBuySide, uint256 amountOut) internal {
        uint256 remaining = isBuySide ? config.buyLiquidityRemaining : config.sellLiquidityRemaining;
        require(amountOut <= remaining, "ARM: Insufficient liquidity");

        remaining -= amountOut;
        if (isBuySide) config.buyLiquidityRemaining = SafeCast.toUint128(remaining);
        else config.sellLiquidityRemaining = SafeCast.toUint128(remaining);
    }

    /// @dev Convert base shares to liquidity assets, bypassing the adapter for pegged assets.
    /// @param config Base asset config that controls conversion behavior.
    /// @param shares Base asset share amount.
    /// @return assets Liquidity-denominated asset amount.
    function _convertToAssets(BaseAssetConfig memory config, uint256 shares) internal view returns (uint256 assets) {
        if (config.peggedToLiquidityAsset) return shares;
        return IAssetAdapter(config.adapter).convertToAssets(shares);
    }

    /// @dev Convert liquidity assets to base shares, bypassing the adapter for pegged assets.
    /// @param config Base asset config that controls conversion behavior.
    /// @param assets Liquidity-denominated asset amount.
    /// @return shares Base asset share amount.
    function _convertToShares(BaseAssetConfig memory config, uint256 assets) internal view returns (uint256 shares) {
        if (config.peggedToLiquidityAsset) return assets;
        return IAssetAdapter(config.adapter).convertToShares(assets);
    }

    /// @dev Accrue fees on discounted buy-side swaps using the recognized NAV gain.
    /// @param buyPrice Price the ARM paid for the base asset.
    /// @param crossPrice Price used to value the base asset in totalAssets().
    /// @param amountOut Liquidity asset amount paid out by the ARM.
    function _accrueSwapFee(uint256 buyPrice, uint256 crossPrice, uint256 amountOut) internal {
        uint256 feeMultiplier =
            buyPrice == 0 ? 0 : (crossPrice - buyPrice) * uint256(fee) * PRICE_SCALE / (buyPrice * FEE_SCALE);
        feesAccrued = SafeCast.toUint128(feesAccrued + amountOut * feeMultiplier / PRICE_SCALE);
    }

    ////////////////////////////////////////////////////
    ///                 Base Asset Admin
    ////////////////////////////////////////////////////

    /// @notice Register a supported base asset and its redemption adapter.
    /// @param newBaseAsset Base asset to support.
    /// @param adapter Asset adapter for conversions and protocol redemption requests.
    /// @param buyPrice Price the ARM pays when buying this base asset from traders.
    /// eg 0.998e36 is 0.998 liquidity asset per base asset.
    /// @param sellPrice Price the ARM charges when selling this base asset to traders.
    /// eg 1e36 is 1 liquidity asset per base asset.
    /// @param buyAmount Liquidity-asset amount the ARM can pay out at the buy price.
    /// eg 100e18 allows the ARM to pay out 100 liquidity assets.
    /// @param sellAmount Base-asset amount the ARM can sell at the sell price.
    /// eg 100e18 allows the ARM to sell 100 base assets.
    /// @param newCrossPrice totalAssets() valuation price for this base asset.
    /// eg 1e36 values the base asset at 1 liquidity asset.
    /// @param peggedToLiquidityAsset True for 1:1 assets that should skip adapter conversion calls.
    function addBaseAsset(
        address newBaseAsset,
        address adapter,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 buyAmount,
        uint256 sellAmount,
        uint256 newCrossPrice,
        bool peggedToLiquidityAsset
    ) external onlyOwner {
        require(newBaseAsset != address(0), "ARM: invalid asset");
        require(adapter != address(0), "ARM: invalid adapter");
        require(baseAssetConfigs[newBaseAsset].adapter == address(0), "ARM: asset already supported");
        require(IERC20(newBaseAsset).decimals() == 18, "ARM: invalid asset decimals");
        require(IAssetAdapter(adapter).asset() == liquidityAsset, "ARM: invalid adapter asset");
        require(newCrossPrice >= PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, "ARM: cross price too low");
        require(newCrossPrice <= PRICE_SCALE, "ARM: cross price too high");
        require(sellPrice >= newCrossPrice, "ARM: sell price too low");
        require(buyPrice < newCrossPrice, "ARM: buy price too high");

        baseAssets.push(newBaseAsset);
        // Allow the adapter to pull base assets when requesting protocol redemptions.
        IERC20(newBaseAsset).approve(adapter, type(uint256).max);
        baseAssetConfigs[newBaseAsset] = BaseAssetConfig({
            buyPrice: SafeCast.toUint128(buyPrice),
            sellPrice: SafeCast.toUint128(sellPrice),
            buyLiquidityRemaining: SafeCast.toUint128(buyAmount),
            sellLiquidityRemaining: SafeCast.toUint128(sellAmount),
            crossPrice: SafeCast.toUint128(newCrossPrice),
            pendingRedeemAssets: 0,
            peggedToLiquidityAsset: peggedToLiquidityAsset,
            adapter: adapter
        });

        emit BaseAssetAdded(newBaseAsset, adapter, buyPrice, sellPrice, newCrossPrice, peggedToLiquidityAsset);
    }

    /// @notice Set buy/sell prices and per-price liquidity limits for a supported base asset.
    /// @param priceBaseAsset Base asset whose prices are being updated.
    /// @param buyPrice Price the ARM pays when buying this base asset from traders.
    /// eg 0.998e36 is 0.998 liquidity asset per base asset.
    /// @param sellPrice Price the ARM charges when selling this base asset to traders.
    /// eg 1e36 is 1 liquidity asset per base asset.
    /// @param buyAmount Liquidity-asset amount the ARM can pay out at the buy price.
    /// eg 100e18 allows the ARM to pay out 100 liquidity assets.
    /// @param sellAmount Base-asset amount the ARM can sell at the sell price.
    /// eg 100e18 allows the ARM to sell 100 base assets.
    function setPrices(
        address priceBaseAsset,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 buyAmount,
        uint256 sellAmount
    ) external onlyOperatorOrOwner {
        BaseAssetConfig storage config = baseAssetConfigs[priceBaseAsset];
        require(config.adapter != address(0), "ARM: unsupported asset");
        require(sellPrice >= config.crossPrice, "ARM: sell price too low");
        require(buyPrice < config.crossPrice, "ARM: buy price too high");

        config.buyPrice = SafeCast.toUint128(buyPrice);
        config.sellPrice = SafeCast.toUint128(sellPrice);
        config.buyLiquidityRemaining = SafeCast.toUint128(buyAmount);
        config.sellLiquidityRemaining = SafeCast.toUint128(sellAmount);

        emit TraderateChanged(priceBaseAsset, buyPrice, sellPrice);
    }

    /// @notice Set the valuation price that buy and sell prices may not cross for a base asset.
    /// @dev When lowering cross price, the ARM must not hold a meaningful balance of that base asset.
    /// @param priceBaseAsset Base asset whose cross price is being updated.
    /// @param newCrossPrice New valuation price scaled to 36 decimals.
    /// eg 1e36 values the base asset at 1 liquidity asset.
    function setCrossPrice(address priceBaseAsset, uint256 newCrossPrice) external onlyOwner {
        BaseAssetConfig storage config = baseAssetConfigs[priceBaseAsset];
        require(config.adapter != address(0), "ARM: unsupported asset");
        require(newCrossPrice >= PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, "ARM: cross price too low");
        require(newCrossPrice <= PRICE_SCALE, "ARM: cross price too high");
        require(config.sellPrice >= newCrossPrice, "ARM: sell price too low");
        require(config.buyPrice < newCrossPrice, "ARM: buy price too high");

        if (newCrossPrice < config.crossPrice) {
            require(IERC20(priceBaseAsset).balanceOf(address(this)) < MIN_TOTAL_SUPPLY, "ARM: too many base assets");
        }

        config.crossPrice = SafeCast.toUint128(newCrossPrice);
        emit CrossPriceUpdated(priceBaseAsset, newCrossPrice);
    }

    ////////////////////////////////////////////////////
    ///                 Adapter Redeems
    ////////////////////////////////////////////////////

    /// @notice Request protocol redemption of a base asset through its adapter.
    /// @dev Increases `pendingRedeemAssets` by the liquidity-denominated amount expected from the adapter.
    /// @param redeemBaseAsset Base asset to redeem through its adapter.
    /// @param shares Base asset shares to submit for protocol redemption.
    /// @return sharesRequested Base asset shares accepted by the adapter.
    /// @return assetsExpected Liquidity-denominated assets expected from the redemption.
    function requestBaseAssetRedeem(address redeemBaseAsset, uint256 shares)
        external
        onlyOperatorOrOwner
        returns (uint256 sharesRequested, uint256 assetsExpected)
    {
        BaseAssetConfig storage config = baseAssetConfigs[redeemBaseAsset];
        require(config.adapter != address(0), "ARM: unsupported asset");

        (sharesRequested, assetsExpected) = IAssetAdapter(config.adapter).requestRedeem(shares);
        // Track the liquidity-denominated value expected back from the adapter queue.
        config.pendingRedeemAssets = SafeCast.toUint120(uint256(config.pendingRedeemAssets) + assetsExpected);
    }

    /// @notice Claim protocol redemptions through a base asset adapter.
    /// @dev Decreases `pendingRedeemAssets` by expected assets. If a protocol returns less than expected,
    /// the shortfall naturally reduces totalAssets() once the pending amount is removed.
    /// @param redeemBaseAsset Base asset whose adapter redemption should be claimed.
    /// @param shares Base asset shares to claim from the adapter's FIFO queue.
    /// @return sharesClaimed Base asset shares claimed by the adapter.
    /// @return assetsExpected Liquidity-denominated assets expected from the claimed redemptions.
    /// @return assetsReceived Liquidity assets actually received by the ARM.
    function claimBaseAssetRedeem(address redeemBaseAsset, uint256 shares)
        external
        onlyOperatorOrOwner
        returns (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived)
    {
        BaseAssetConfig storage config = baseAssetConfigs[redeemBaseAsset];
        require(config.adapter != address(0), "ARM: unsupported asset");

        (sharesClaimed, assetsExpected, assetsReceived) = IAssetAdapter(config.adapter).redeem(shares);
        // Remove expected queue value. Any received shortfall remains reflected in totalAssets().
        config.pendingRedeemAssets = SafeCast.toUint120(uint256(config.pendingRedeemAssets) - assetsExpected);
    }

    ////////////////////////////////////////////////////
    ///                 LP Deposits
    ////////////////////////////////////////////////////

    /// @notice Preview LP shares minted for a liquidity-asset deposit.
    /// @param assets Liquidity assets to deposit.
    /// @return shares LP shares that would be minted.
    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        shares = convertToShares(assets);
    }

    /// @notice Deposit liquidity assets and mint LP shares to the caller.
    /// @param assets Liquidity assets to deposit.
    /// @return shares LP shares minted.
    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = _deposit(assets, msg.sender);
    }

    /// @notice Deposit liquidity assets and mint LP shares to `receiver`.
    /// @param assets Liquidity assets to deposit.
    /// @param receiver Account that receives minted LP shares.
    /// @return shares LP shares minted.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = _deposit(assets, receiver);
    }

    /// @dev Internal liquidity deposit implementation.
    /// @param assets Liquidity assets to deposit.
    /// @param receiver Account that receives minted LP shares.
    /// @return shares LP shares minted.
    function _deposit(uint256 assets, address receiver) internal returns (uint256 shares) {
        require(totalAssets() > MIN_TOTAL_SUPPLY || reservedWithdrawLiquidity == 0, "ARM: insolvent");
        shares = convertToShares(assets);
        require(shares != 0, "ARM: zero shares");

        // Transfer liquidity from the depositor before minting LP shares.
        IERC20(liquidityAsset).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);

        // Enforce LP caps after the deposit has changed the receiver's share balance.
        if (capManager != address(0)) ICapManager(capManager).postDepositHook(receiver, assets);
        emit Deposit(receiver, assets, shares);
    }

    ////////////////////////////////////////////////////
    ///                 LP Redeems
    ////////////////////////////////////////////////////

    /// @notice Preview liquidity assets redeemable for LP shares.
    /// @param shares LP shares to redeem.
    /// @return assets Liquidity assets that would be redeemable.
    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

    /// @notice Request to redeem LP shares for liquidity assets after the claim delay.
    /// @param shares LP shares to burn.
    /// @return requestId The LP withdrawal request id.
    /// @return assets The maximum liquidity assets claimable by the redeemer.
    function requestRedeem(uint256 shares) external returns (uint256 requestId, uint256 assets) {
        assets = convertToAssets(shares);
        requestId = nextWithdrawalIndex;
        // Store the next withdrawal request id.
        nextWithdrawalIndex = requestId + 1;

        // Cumulative shares queued including this request, used for the FIFO gate at claim.
        uint128 queued = SafeCast.toUint128(withdrawsQueuedShares + shares);
        withdrawsQueuedShares = queued;
        // Reserve the request-time maximum liquidity payout.
        reservedWithdrawLiquidity += assets;

        uint40 claimTimestamp = uint40(block.timestamp + claimDelay);
        withdrawalRequests[requestId] = WithdrawalRequest({
            withdrawer: msg.sender,
            claimed: false,
            claimTimestamp: claimTimestamp,
            assets: SafeCast.toUint128(assets),
            queued: queued,
            shares: SafeCast.toUint128(shares)
        });

        // Escrow the redeemer's shares so they stay in totalSupply() and share losses/gains pro-rata.
        _transfer(msg.sender, address(this), shares);
        emit RedeemRequested(msg.sender, requestId, assets, queued, claimTimestamp);
    }

    /// @notice Claim liquidity assets from a matured LP withdrawal request.
    /// @dev If assets per share decreased after request time, the claim uses the lower claim-time value.
    /// @param requestId LP withdrawal request id to claim.
    /// @return assets Liquidity assets transferred to the requester.
    function claimRedeem(uint256 requestId) external returns (uint256 assets) {
        WithdrawalRequest memory request = withdrawalRequests[requestId];

        require(request.claimTimestamp <= block.timestamp, "Claim delay not met");
        require(request.queued <= claimable(), "Queue pending liquidity");
        require(request.withdrawer == msg.sender, "Not requester");
        require(request.claimed == false, "Already claimed");

        // In the scenario where the ARM has made a loss after the redeem request, the asset value of
        // the redeemed shares at the time of the claim is used.
        // This can happen if there was a significant slashing event on the base asset, eg stETH,
        // after the redeem request was made.
        uint256 assetsAtClaim = request.shares > 0 ? convertToAssets(request.shares) : request.assets;
        // Use the minimum of the asset value of the redeemed shares at request or claim.
        assets = request.assets < assetsAtClaim ? request.assets : assetsAtClaim;

        // Store the request as claimed.
        withdrawalRequests[requestId].claimed = true;
        // Release the full request-time reservation, even when a loss-adjusted payout is lower.
        reservedWithdrawLiquidity -= request.assets;
        // Cumulative claimed amount in shares, used by the FIFO gate above.
        withdrawsClaimedShares += request.shares;

        // Burn the escrowed shares after `assets` was computed so conversion uses the pre-claim supply.
        _burn(address(this), request.shares);

        // If there is not enough liquidity assets in the ARM, get from the active market if one is configured.
        // Read the active market address from storage once to save gas.
        address activeMarketMem = activeMarket;
        if (activeMarketMem != address(0)) {
            uint256 liquidityInARM = IERC20(liquidityAsset).balanceOf(address(this));
            if (assets > liquidityInARM) {
                uint256 liquidityFromMarket = assets - liquidityInARM;
                // This should work as we have checked earlier the claimable liquidity which includes the active market.
                IERC4626(activeMarketMem).withdraw(liquidityFromMarket, address(this), address(this));
            }
        }

        // Transfer the liquidity asset to the withdrawer.
        IERC20(liquidityAsset).transfer(msg.sender, assets);
        emit RedeemClaimed(msg.sender, requestId, assets);
    }

    ////////////////////////////////////////////////////
    ///                 Accounting
    ////////////////////////////////////////////////////

    /// @notice Cumulative share queue frontier currently backed by claimable liquidity.
    /// @return claimableShares Requests with `queued <= claimableShares` can be claimed once their delay has elapsed.
    function claimable() public view returns (uint256 claimableShares) {
        uint256 claimableLiquidity = IERC20(liquidityAsset).balanceOf(address(this));

        // If there is an active lending market, add to the claimable amount.
        address activeMarketMem = activeMarket;
        if (activeMarketMem != address(0)) {
            // maxWithdraw is used as during periods of high utilization or temporary pauses,
            // maxWithdraw may return less than convertToAssets.
            claimableLiquidity += IERC4626(activeMarketMem).maxWithdraw(address(this));
        }

        claimableShares = withdrawsClaimedShares + convertToShares(claimableLiquidity);
    }

    /// @notice Get available liquidity and base asset reserves for a supported base asset.
    /// @param reserveBaseAsset Supported base asset whose reserve should be returned.
    /// @return liquidityAssets Available liquidity assets net of outstanding LP withdrawal claims.
    /// @return baseAssetReserve Base assets held directly by the ARM.
    function getReserves(address reserveBaseAsset)
        external
        view
        returns (uint256 liquidityAssets, uint256 baseAssetReserve)
    {
        require(baseAssetConfigs[reserveBaseAsset].adapter != address(0), "ARM: unsupported asset");

        liquidityAssets = IERC20(liquidityAsset).balanceOf(address(this));

        address activeMarketMem = activeMarket;
        if (activeMarketMem != address(0)) {
            // maxWithdraw is used because reserve liquidity should reflect what can currently be pulled.
            liquidityAssets += IERC4626(activeMarketMem).maxWithdraw(address(this));
        }

        uint256 reservedWithdrawLiquidityMem = reservedWithdrawLiquidity;
        liquidityAssets =
            reservedWithdrawLiquidityMem > liquidityAssets ? 0 : liquidityAssets - reservedWithdrawLiquidityMem;
        baseAssetReserve = IERC20(reserveBaseAsset).balanceOf(address(this));
    }

    /// @dev Ensure swaps and fee collection do not consume liquidity reserved for LP withdrawal claims.
    /// If no outstanding withdrawals exist, no balance check is done. This is a gas optimization for swaps.
    /// There is no liquidity guarantee for the fee collector. If there is not enough unreserved liquidity
    /// to collect accrued fees, the fee collector has to wait until enough liquidity is available.
    /// @param amount Liquidity asset amount that must be unreserved.
    function _requireLiquidityAvailable(uint256 amount) internal view {
        // Liquidity assets still reserved for unclaimed LP withdrawal requests.
        uint256 reservedWithdrawLiquidityMem = reservedWithdrawLiquidity;
        // Save gas on an external balanceOf call if there are no outstanding withdrawals.
        if (reservedWithdrawLiquidityMem == 0) return;

        // Ensure the ARM can cover both the requested amount and outstanding LP withdrawals.
        require(
            amount + reservedWithdrawLiquidityMem <= IERC20(liquidityAsset).balanceOf(address(this)),
            "ARM: Insufficient liquidity"
        );
    }

    /// @notice Economic value of ARM assets net of accrued swap fees.
    /// @return Total liquidity-denominated assets available to LP shares.
    function totalAssets() public view virtual returns (uint256) {
        uint256 newAvailableAssets = _availableAssets();
        uint256 feesAccruedMem = feesAccrued;
        // total assets should only go up from the initial deposit amount that is burnt,
        // but in case of something unforeseen, return at least MIN_TOTAL_SUPPLY.
        // An example scenario that will return MIN_TOTAL_SUPPLY is:
        // First LP deposits and then requests a redeem of all their ARM shares.
        // While waiting to claim their request, the ARM suffers a loss of assets. eg lending market loss.
        // When they claim their request, newAvailableAssets can be zero as the ARM assets can be less than
        // the outstanding withdrawal request that was calculated before the loss.
        if (feesAccruedMem + MIN_TOTAL_SUPPLY >= newAvailableAssets) return MIN_TOTAL_SUPPLY;
        // Remove accrued swap fees from the available assets.
        return newAvailableAssets - feesAccruedMem;
    }

    /// @notice Liquidity asset used for LP deposits and redeems.
    /// @dev ERC-4626 compatibility view.
    /// @return The liquidity asset address.
    function asset() external view virtual returns (address) {
        return liquidityAsset;
    }

    /// @dev Calculate ARM asset value before accrued swap fees are removed.
    /// Includes on-hand liquidity, active market value, base balances valued at cross price, and adapter queues.
    /// Queued redemption shares stay in totalSupply(), so the share price already reflects outstanding claims.
    /// @return availableAssets Liquidity-denominated assets before accrued swap fees.
    function _availableAssets() internal view returns (uint256 availableAssets) {
        availableAssets = IERC20(liquidityAsset).balanceOf(address(this));

        uint256 length = baseAssets.length;
        for (uint256 i = 0; i < length; ++i) {
            address supportedBaseAsset = baseAssets[i];
            BaseAssetConfig memory config = baseAssetConfigs[supportedBaseAsset];
            // Base assets in the ARM are converted to liquidity assets and then the cross price is applied.
            // The cross price is the discounted price for the redemption time delay. This ensures the ARM's
            // assets per share does not decrease if the ARM sells base assets at a discount, because the base
            // sell price is greater than or equal to the cross price.
            uint256 baseConvertedToLiquid =
                _convertToAssets(config, IERC20(supportedBaseAsset).balanceOf(address(this)));
            availableAssets += baseConvertedToLiquid * config.crossPrice / PRICE_SCALE;
            // Pending adapter redemptions are already tracked in liquidity terms and represent assets
            // expected back from protocol withdrawal queues. Value them at the live cross price so moving
            // base assets into a withdrawal queue does not create an immediate assets-per-share increase.
            availableAssets += uint256(config.pendingRedeemAssets) * config.crossPrice / PRICE_SCALE;
        }

        address activeMarketMem = activeMarket;
        if (activeMarketMem != address(0)) {
            // Get all the active lending market shares owned by this ARM contract.
            uint256 allShares = IERC4626(activeMarketMem).balanceOf(address(this));
            // Value active market shares economically, not by currently withdrawable liquidity.
            // Liquidity-aware functions such as claimable() and _allocate() continue to use maxWithdraw,
            // maxRedeem, withdraw and redeem when current liquidity matters.
            availableAssets += IERC4626(activeMarketMem).convertToAssets(allShares);
        }
    }

    /// @notice Convert liquidity assets to LP shares.
    /// @param assets Liquidity assets to convert.
    /// @return shares LP shares equivalent to `assets`.
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = assets * totalSupply() / totalAssets();
    }

    /// @notice Convert LP shares to liquidity assets.
    /// @param shares LP shares to convert.
    /// @return assets Liquidity assets equivalent to `shares`.
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = shares * totalAssets() / totalSupply();
    }

    ////////////////////////////////////////////////////
    ///                 Fees
    ////////////////////////////////////////////////////

    /// @notice Set the fee on discounted base-asset buy swaps.
    /// @param _fee Fee measured in basis points. Maximum is 50%.
    /// 10,000 = 100% fee
    /// 500 = 5% fee
    function setFee(uint256 _fee) external onlyOwner {
        _setFee(_fee);
    }

    /// @notice Set the fee collector account.
    /// @param _feeCollector Account or contract that receives accrued swap fees.
    function setFeeCollector(address _feeCollector) external onlyOwner {
        _setFeeCollector(_feeCollector);
    }

    /// @param _fee Fee measured in basis points. Maximum is 50%.
    /// 10,000 = 100% fee
    /// 500 = 5% fee
    function _setFee(uint256 _fee) internal {
        require(_fee <= FEE_SCALE / 2, "ARM: fee too high");
        collectFees();
        fee = SafeCast.toUint16(_fee);
        emit FeeUpdated(_fee);
    }

    /// @param _feeCollector Account or contract that receives accrued swap fees.
    function _setFeeCollector(address _feeCollector) internal {
        require(_feeCollector != address(0), "ARM: invalid fee collector");
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(_feeCollector);
    }

    /// @notice Transfer accrued swap fees to the fee collector.
    /// @return fees Liquidity assets transferred to the fee collector.
    function collectFees() public returns (uint256 fees) {
        fees = feesAccrued;
        if (fees == 0) return 0;

        // Fees can only be collected from unreserved on-hand liquidity.
        _requireLiquidityAvailable(fees);
        require(fees <= IERC20(liquidityAsset).balanceOf(address(this)), "ARM: insufficient liquidity");

        feesAccrued = 0;
        IERC20(liquidityAsset).transfer(feeCollector, fees);
        emit FeeCollected(feeCollector, fees);
    }

    ////////////////////////////////////////////////////
    ///                 Active Markets
    ////////////////////////////////////////////////////

    /// @notice Add supported ERC-4626 lending markets.
    /// @param _markets Market addresses to support.
    function addMarkets(address[] calldata _markets) external onlyOwner {
        for (uint256 i = 0; i < _markets.length; ++i) {
            address market = _markets[i];
            require(market != address(0), "ARM: invalid market");
            require(!supportedMarkets[market], "ARM: market already supported");
            require(IERC4626(market).asset() == liquidityAsset, "ARM: invalid market asset");

            supportedMarkets[market] = true;
            emit MarketAdded(market);
        }
    }

    /// @notice Remove a supported ERC-4626 lending market.
    /// @param _market Market address to remove.
    function removeMarket(address _market) external onlyOwner {
        require(_market != address(0), "ARM: invalid market");
        require(supportedMarkets[_market], "ARM: market not supported");
        require(_market != activeMarket, "ARM: market in active");

        supportedMarkets[_market] = false;
        emit MarketRemoved(_market);
    }

    /// @notice Set the active lending market used for allocation.
    /// @dev Redeems all shares from the previous market before switching.
    /// @param _market Supported market to activate, or address(0) to disable active allocation.
    function setActiveMarket(address _market) external onlyOperatorOrOwner {
        require(_market == address(0) || supportedMarkets[_market], "ARM: market not supported");
        // Read once from storage to save gas and make it clear this is the previous active market.
        address previousActiveMarket = activeMarket;
        // Don't revert if the previous active market is the same as the new one.
        if (previousActiveMarket == _market) return;

        if (previousActiveMarket != address(0)) {
            // Redeem all shares from the previous active lending market.
            // balanceOf is used instead of maxRedeem to ensure all shares are redeemed.
            // maxRedeem can return a smaller amount of shares than balanceOf if the market is highly utilized.
            uint256 shares = IERC4626(previousActiveMarket).balanceOf(address(this));
            if (shares > 0) {
                // This could fail if the market has high utilization. In this case, the Operator needs
                // to wait until the utilization drops before setting a new active market.
                // The redeem can also fail if the ARM has a dust amount of shares left. eg 100 wei.
                // If that happens, the Operator can transfer a tiny amount of active market shares
                // to the ARM so the following redeem will not fail.
                IERC4626(previousActiveMarket).redeem(shares, address(this), address(this));
            }
        }

        activeMarket = _market;
        emit ActiveMarketUpdated(_market);

        // Exit if no new active market.
        if (_market == address(0)) return;

        _allocate();
    }

    /// @notice Allocate liquidity to or from the active market based on the ARM buffer.
    /// @dev The buffer excludes liquidity assets reserved for the ARM's withdrawal queue. That is, more
    /// liquidity assets will be withdrawn from the lending market if the ARM's liquidity asset balance
    /// does not cover the buffer, which can be zero, and the ARM's outstanding withdrawals.
    /// @return targetLiquidityDelta Desired liquidity movement. Positive means deposit, negative means withdraw.
    /// @return actualLiquidityDelta Actual liquidity movement. Positive means deposited, negative means withdrawn.
    function allocate() external returns (int256 targetLiquidityDelta, int256 actualLiquidityDelta) {
        require(activeMarket != address(0), "ARM: no active market");
        return _allocate();
    }

    /// @dev Internal allocation implementation.
    /// @return targetLiquidityDelta Desired liquidity movement. Positive means deposit, negative means withdraw.
    /// @return actualLiquidityDelta Actual liquidity movement. Positive means deposited, negative means withdrawn.
    function _allocate() internal returns (int256 targetLiquidityDelta, int256 actualLiquidityDelta) {
        uint256 availableAssets = _availableAssets();
        if (availableAssets == 0) return (0, 0);

        uint256 targetArmLiquidity = availableAssets * armBuffer / 1e18;
        // The current liquidity available to swap is the liquidity asset balance less
        // any outstanding withdrawals from the ARM's withdrawal queue.
        int256 currentArmLiquidity = SafeCast.toInt256(IERC20(liquidityAsset).balanceOf(address(this)))
            - SafeCast.toInt256(reservedWithdrawLiquidity);

        targetLiquidityDelta = currentArmLiquidity - SafeCast.toInt256(targetArmLiquidity);

        // Load the active lending market address from storage to save gas
        address activeMarketMem = activeMarket;

        // The allocateThreshold prevents the ARM from constantly depositing and withdrawing if there are rounding issues
        if (targetLiquidityDelta > allocateThreshold) {
            // We have too much liquidity in the ARM, so deposit some to the active lending market.
            uint256 depositAmount = SafeCast.toUint256(targetLiquidityDelta);
            IERC20(liquidityAsset).approve(activeMarketMem, depositAmount);
            IERC4626(activeMarketMem).deposit(depositAmount, address(this));
            actualLiquidityDelta = SafeCast.toInt256(depositAmount);
        } else if (targetLiquidityDelta < 0) {
            // We have too little liquidity in the ARM, so withdraw some from the active lending market.
            uint256 availableMarketAssets = IERC4626(activeMarketMem).maxWithdraw(address(this));
            uint256 desiredWithdrawAmount = SafeCast.toUint256(-targetLiquidityDelta);

            if (availableMarketAssets < desiredWithdrawAmount) {
                // Not enough assets in the market so redeem as much as possible.
                // maxRedeem is used instead of balanceOf as we want to redeem as much as possible without failing.
                // redeem of the ARM's balance can fail if the lending market is highly utilized or temporarily paused.
                // Redeem and not withdrawal is used to avoid leaving a small amount of assets in the market.
                uint256 shares = IERC4626(activeMarketMem).maxRedeem(address(this));
                if (shares <= minSharesToRedeem) return (targetLiquidityDelta, 0);
                // This should not fail according to the ERC-4626 spec as maxRedeem was used earlier
                // but it depends on the 4626 implementation of the lending market.
                // It may fail if the market is highly utilized and not compliant with 4626.
                uint256 redeemedAssets = IERC4626(activeMarketMem).redeem(shares, address(this), address(this));
                actualLiquidityDelta = -SafeCast.toInt256(redeemedAssets);
            } else {
                IERC4626(activeMarketMem).withdraw(desiredWithdrawAmount, address(this), address(this));
                actualLiquidityDelta = -SafeCast.toInt256(desiredWithdrawAmount);
            }
        }

        emit Allocated(activeMarketMem, targetLiquidityDelta, actualLiquidityDelta);
    }

    ////////////////////////////////////////////////////
    ///                 Admin Functions
    ////////////////////////////////////////////////////

    /// @notice Set the CapManager contract.
    /// @param _capManager CapManager contract address, or address(0) to disable caps.
    function setCapManager(address _capManager) external onlyOwner {
        capManager = _capManager;
        emit CapManagerUpdated(_capManager);
    }

    /// @notice Set the percentage of available liquidity assets to keep on hand. 100% = 1e18.
    /// @param _armBuffer Percentage of available assets to keep in the ARM, scaled by 1e18.
    /// 1e18 = 100% buffer
    /// 0.1e18 = 10% buffer
    function setARMBuffer(uint256 _armBuffer) external onlyOperatorOrOwner {
        require(_armBuffer <= 1e18, "ARM: invalid arm buffer");
        armBuffer = _armBuffer;
        emit ARMBufferUpdated(_armBuffer);
    }

    /// @notice Clear the legacy packed asset queue counter slot during the Model A upgrade.
    /// @dev The reused slot previously packed `withdrawsQueued` in the low 128 bits and
    /// `withdrawsClaimed` in the high 128 bits. It may be nonzero even when the old queue
    /// is fully drained, so upgrade scripts should call this with `upgradeToAndCall`.
    function migrateLegacyWithdrawQueue() external onlyOwner {
        require(withdrawsQueuedShares == 0 && withdrawsClaimedShares == 0, "ARM: already migrated");

        uint256 packedLegacyQueue = reservedWithdrawLiquidity;
        uint128 legacyQueued = uint128(packedLegacyQueue);
        uint128 legacyClaimed = uint128(packedLegacyQueue >> 128);
        require(legacyQueued == legacyClaimed, "ARM: legacy withdrawals pending");

        reservedWithdrawLiquidity = 0;
    }
}
