// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {OwnableOperable} from "./OwnableOperable.sol";
import {IAsyncRedeemVault, IERC20, ICapManager} from "./Interfaces.sol";

/**
 * @title Generic multi-asset Automated Redemption Manager (ARM)
 * @author Origin Protocol Inc
 */
abstract contract AbstractMultiAssetARM is OwnableOperable, ERC20Upgradeable {
    /// @notice Maximum amount the Owner can set a base asset cross price below 1.0, scaled to 36 decimals.
    uint256 public constant MAX_CROSS_PRICE_DEVIATION = 20e32;
    /// @notice Scale used for all ARM prices.
    uint256 public constant PRICE_SCALE = 1e36;
    /// @notice Minimum total supply permanently minted to the dead address to prevent donation attacks.
    uint256 internal constant MIN_TOTAL_SUPPLY = 1e12;
    /// @notice Address that receives the permanent minimum-share mint.
    address internal constant DEAD_ACCOUNT = 0x000000000000000000000000000000000000dEaD;
    /// @notice Scale for the performance fee where 10,000 = 100%.
    uint256 public constant FEE_SCALE = 10000;

    /// @notice Minimum amount of lending market shares that can be redeemed when liquidity must be pulled back.
    uint256 public immutable minSharesToRedeem;
    /// @notice Minimum positive liquidity delta required before allocating into the active lending market.
    int256 public immutable allocateThreshold;
    /// @notice Shared asset used for LP deposits, LP redeems, and as the quote asset in swaps.
    address public immutable liquidityAsset;
    /// @notice Cached decimals for the shared liquidity asset.
    uint8 internal immutable liquidityAssetDecimals;
    /// @notice Delay between LP redeem request and LP redeem claim.
    uint256 public immutable claimDelay;

    /// @notice Configuration and accounting state for a supported base asset.
    struct BaseAssetConfig {
        /// @notice Whether the base asset is currently supported.
        bool supported;
        /// @notice Async vault used to convert the base asset back into the liquidity asset.
        address vault;
        /// @notice Price the ARM pays when buying the base asset, scaled to 36 decimals.
        uint256 buyPrice;
        /// @notice Price the ARM charges when selling the base asset, scaled to 36 decimals.
        uint256 sellPrice;
        /// @notice Anchor price used for accounting and price-cross validation, scaled to 36 decimals.
        uint256 crossPrice;
        /// @notice Total requested vault shares that have not yet been claimed back as liquidity.
        uint256 requestedVaultShares;
    }

    /// @notice Total LP redeem assets queued, including already claimed requests.
    uint128 public withdrawsQueued;
    /// @notice Total LP redeem assets already claimed.
    uint128 public withdrawsClaimed;
    /// @notice Index assigned to the next LP redeem request.
    uint256 public nextWithdrawalIndex;

    /// @notice LP redeem request state.
    struct WithdrawalRequest {
        /// @notice LP that created the request.
        address withdrawer;
        /// @notice Whether the request has already been claimed.
        bool claimed;
        /// @notice Earliest timestamp the request can be claimed.
        uint40 claimTimestamp;
        /// @notice Liquidity asset amount reserved for the request when it was created.
        uint128 assets;
        /// @notice Cumulative queued amount including this request.
        uint128 queued;
        /// @notice Shares burned when the request was created.
        uint128 shares;
    }

    /// @notice Mapping of LP redeem request IDs to stored redeem request data.
    mapping(uint256 requestId => WithdrawalRequest) public withdrawalRequests;

    /// @notice Performance fee rate measured in basis points.
    uint16 public fee;
    /// @notice Available assets snapshot used to accrue performance fees net of LP deposits and redeems.
    int128 public lastAvailableAssets;
    /// @notice Recipient of collected performance fees.
    address public feeCollector;
    /// @notice Optional cap manager invoked after LP deposits.
    address public capManager;

    /// @notice Lending market currently used for excess liquidity allocation.
    address public activeMarket;
    /// @notice Set of lending markets approved for use by the ARM.
    mapping(address market => bool supported) public supportedMarkets;
    /// @notice Fraction of available assets to keep on hand in the ARM, scaled by 1e18.
    uint256 public armBuffer;

    /// @notice List of currently supported base assets.
    address[] internal supportedBaseAssets;
    /// @notice Configuration for each supported base asset.
    mapping(address asset => BaseAssetConfig) public baseAssetConfigs;
    /// @notice One-based index of each supported base asset in `supportedBaseAssets`.
    mapping(address asset => uint256 indexPlusOne) internal supportedBaseAssetIndex;

    /// @dev Storage gap reserved for future upgrades.
    uint256[34] private _gap;

    /// @notice Emitted when a new base asset is added.
    event BaseAssetAdded(address indexed asset, address indexed vault, uint256 buyPrice, uint256 sellPrice, uint256 crossPrice);
    /// @notice Emitted when a base asset is removed.
    event BaseAssetRemoved(address indexed asset);
    /// @notice Emitted when a base asset's buy and sell prices are updated.
    event PricesUpdated(address indexed asset, uint256 buyPrice, uint256 sellPrice);
    /// @notice Emitted when a base asset's cross price is updated.
    event CrossPriceUpdated(address indexed asset, uint256 crossPrice);
    /// @notice Emitted when LP shares are minted for a liquidity deposit.
    event Deposit(address indexed owner, uint256 assets, uint256 shares);
    /// @notice Emitted when an LP redeem request is created.
    event RedeemRequested(
        address indexed withdrawer, uint256 indexed requestId, uint256 assets, uint256 queued, uint256 claimTimestamp
    );
    /// @notice Emitted when an LP redeem request is claimed.
    event RedeemClaimed(address indexed withdrawer, uint256 indexed requestId, uint256 assets);
    /// @notice Emitted when performance fees are transferred out.
    event FeeCollected(address indexed feeCollector, uint256 fee);
    /// @notice Emitted when the performance fee rate is updated.
    event FeeUpdated(uint256 fee);
    /// @notice Emitted when the fee collector is updated.
    event FeeCollectorUpdated(address indexed newFeeCollector);
    /// @notice Emitted when the cap manager is updated.
    event CapManagerUpdated(address indexed capManager);
    /// @notice Emitted when the active lending market changes.
    event ActiveMarketUpdated(address indexed market);
    /// @notice Emitted when a lending market is added to the supported set.
    event MarketAdded(address indexed market);
    /// @notice Emitted when a lending market is removed from the supported set.
    event MarketRemoved(address indexed market);
    /// @notice Emitted when the target on-hand liquidity buffer changes.
    event ARMBufferUpdated(uint256 armBuffer);
    /// @notice Emitted after a lending market allocation or withdrawal attempt.
    event Allocated(address indexed market, int256 targetLiquidityDelta, int256 actualLiquidityDelta);
    /// @notice Emitted when vault shares are submitted for async redemption.
    event VaultRedeemRequested(address indexed asset, address indexed vault, uint256 shares);
    /// @notice Emitted when previously requested vault shares are claimed back as liquidity.
    event VaultRedeemClaimed(address indexed asset, address indexed vault, uint256 shares, uint256 assets);

    /// @param _liquidityAsset Shared asset used for LP accounting and as the swap quote asset.
    /// @param _claimDelay Delay in seconds before LP redeem requests can be claimed.
    /// @param _minSharesToRedeem Minimum shares redeemable from the active lending market.
    /// @param _allocateThreshold Minimum positive delta required before depositing into the active market.
    constructor(address _liquidityAsset, uint256 _claimDelay, uint256 _minSharesToRedeem, int256 _allocateThreshold) {
        liquidityAsset = _liquidityAsset;
        liquidityAssetDecimals = IERC20(_liquidityAsset).decimals();
        claimDelay = _claimDelay;

        _setOwner(address(0));

        require(_allocateThreshold >= 0, "invalid allocate threshold");
        allocateThreshold = _allocateThreshold;
        minSharesToRedeem = _minSharesToRedeem;
    }

    /// @notice Initializes the proxy storage for a new multi-asset ARM.
    /// @param _operator Account allowed to perform operational actions.
    /// @param _name ERC20 name for the LP share token.
    /// @param _symbol ERC20 symbol for the LP share token.
    /// @param _fee Performance fee in basis points.
    /// @param _feeCollector Recipient of performance fees.
    /// @param _capManager Optional cap manager hook for LP deposits.
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

        IERC20(liquidityAsset).transferFrom(msg.sender, address(this), MIN_TOTAL_SUPPLY);
        _mint(DEAD_ACCOUNT, MIN_TOTAL_SUPPLY);

        (uint256 availableAssets,) = _availableAssets();
        lastAvailableAssets = SafeCast.toInt128(SafeCast.toInt256(availableAssets));
        _setFee(_fee);
        _setFeeCollector(_feeCollector);

        capManager = _capManager;
        emit CapManagerUpdated(_capManager);
    }

    /// @notice Swap an exact amount of one supported token for the paired output token.
    /// @param inToken Input token. Must be the liquidity asset or a supported base asset.
    /// @param outToken Output token. Must be the opposite side of the pair.
    /// @param amountIn Exact input amount.
    /// @param amountOutMin Minimum acceptable output amount.
    /// @param to Recipient of the output tokens.
    /// @return amounts Two-element array of input and output amounts.
    function swapExactTokensForTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external returns (uint256[] memory amounts) {
        uint256 amountOut = _swapExactTokensForTokens(inToken, outToken, amountIn, to);
        require(amountOut >= amountOutMin, "ARM: Insufficient output amount");

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    /// @notice Uniswap V2 compatible exact-input swap entrypoint.
    /// @param amountIn Exact input amount.
    /// @param amountOutMin Minimum acceptable output amount.
    /// @param path Two-token path containing the liquidity asset and a supported base asset.
    /// @param to Recipient of the output tokens.
    /// @param deadline Expiry timestamp for the swap.
    /// @return amounts Two-element array of input and output amounts.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(path.length == 2, "ARM: Invalid path length");
        _inDeadline(deadline);

        IERC20 inToken = IERC20(path[0]);
        IERC20 outToken = IERC20(path[1]);

        uint256 amountOut = _swapExactTokensForTokens(inToken, outToken, amountIn, to);
        require(amountOut >= amountOutMin, "ARM: Insufficient output amount");

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    /// @notice Swap for an exact output amount while spending no more than the max input.
    /// @param inToken Input token. Must be the liquidity asset or a supported base asset.
    /// @param outToken Output token. Must be the opposite side of the pair.
    /// @param amountOut Exact output amount desired.
    /// @param amountInMax Maximum acceptable input amount.
    /// @param to Recipient of the output tokens.
    /// @return amounts Two-element array of input and output amounts.
    function swapTokensForExactTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountOut,
        uint256 amountInMax,
        address to
    ) external returns (uint256[] memory amounts) {
        uint256 amountIn = _swapTokensForExactTokens(inToken, outToken, amountOut, to);
        require(amountIn <= amountInMax, "ARM: Excess input amount");

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    /// @notice Uniswap V2 compatible exact-output swap entrypoint.
    /// @param amountOut Exact output amount desired.
    /// @param amountInMax Maximum acceptable input amount.
    /// @param path Two-token path containing the liquidity asset and a supported base asset.
    /// @param to Recipient of the output tokens.
    /// @param deadline Expiry timestamp for the swap.
    /// @return amounts Two-element array of input and output amounts.
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(path.length == 2, "ARM: Invalid path length");
        _inDeadline(deadline);

        IERC20 inToken = IERC20(path[0]);
        IERC20 outToken = IERC20(path[1]);

        uint256 amountIn = _swapTokensForExactTokens(inToken, outToken, amountOut, to);
        require(amountIn <= amountInMax, "ARM: Excess input amount");

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    /// @notice Reverts if the provided deadline has already passed.
    /// @param deadline Swap deadline to validate.
    function _inDeadline(uint256 deadline) internal view {
        require(deadline >= block.timestamp, "ARM: Deadline expired");
    }

    function _transferAsset(address token, address to, uint256 amount) internal virtual {
        if (token == liquidityAsset) _requireLiquidityAvailable(amount);
        IERC20(token).transfer(to, amount);
    }

    function _transferAssetFrom(address token, address from, address to, uint256 amount) internal virtual {
        IERC20(token).transferFrom(from, to, amount);
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, address to)
        internal
        returns (uint256 amountOut)
    {
        (address baseAsset, bool inIsLiquidity) = _getSwapBaseAsset(address(inToken), address(outToken));
        BaseAssetConfig memory config = baseAssetConfigs[baseAsset];

        if (inIsLiquidity) {
            uint256 convertedAmountIn = IAsyncRedeemVault(config.vault).convertToShares(amountIn);
            amountOut = convertedAmountIn * PRICE_SCALE / config.sellPrice;
        } else {
            uint256 convertedAmountIn = IAsyncRedeemVault(config.vault).convertToAssets(amountIn);
            amountOut = convertedAmountIn * config.buyPrice / PRICE_SCALE;
        }

        _transferAssetFrom(address(inToken), msg.sender, address(this), amountIn);
        _transferAsset(address(outToken), to, amountOut);
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountOut, address to)
        internal
        returns (uint256 amountIn)
    {
        (address baseAsset, bool inIsLiquidity) = _getSwapBaseAsset(address(inToken), address(outToken));
        BaseAssetConfig memory config = baseAssetConfigs[baseAsset];

        if (inIsLiquidity) {
            uint256 convertedAmountOut = IAsyncRedeemVault(config.vault).convertToAssets(amountOut);
            amountIn = ((convertedAmountOut * config.sellPrice) / PRICE_SCALE) + 3;
        } else {
            uint256 convertedAmountOut = IAsyncRedeemVault(config.vault).convertToShares(amountOut);
            amountIn = ((convertedAmountOut * PRICE_SCALE) / config.buyPrice) + 3;
        }

        _transferAssetFrom(address(inToken), msg.sender, address(this), amountIn);
        _transferAsset(address(outToken), to, amountOut);
    }

    function _getSwapBaseAsset(address inToken, address outToken) internal view returns (address baseAsset, bool inIsLiquidity) {
        if (inToken == liquidityAsset && baseAssetConfigs[outToken].supported) {
            return (outToken, true);
        }
        if (outToken == liquidityAsset && baseAssetConfigs[inToken].supported) {
            return (inToken, false);
        }
        revert("ARM: Invalid swap assets");
    }

    /// @notice Returns current swap reserves for a supported base asset pair.
    /// @param baseAsset Supported base asset to inspect.
    /// @return liquidityReserve Unreserved liquidity asset balance held by the ARM.
    /// @return baseReserve Base asset balance held by the ARM.
    function getReserves(address baseAsset) external view returns (uint256 liquidityReserve, uint256 baseReserve) {
        require(baseAssetConfigs[baseAsset].supported, "ARM: unsupported asset");

        uint256 outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;
        uint256 liquidityBalance = IERC20(liquidityAsset).balanceOf(address(this));
        liquidityReserve = outstandingWithdrawals > liquidityBalance ? 0 : liquidityBalance - outstandingWithdrawals;
        baseReserve = IERC20(baseAsset).balanceOf(address(this));
    }

    /// @notice Returns the full list of supported base assets.
    /// @return Array of supported base asset addresses.
    function getSupportedBaseAssets() external view returns (address[] memory) {
        return supportedBaseAssets;
    }

    /// @notice Adds a new supported base asset and its async redeem vault.
    /// @param baseAsset New base asset to support.
    /// @param vault Async vault used to redeem the base asset into the liquidity asset.
    /// @param buyPrice Initial buy price for the base asset.
    /// @param sellPrice Initial sell price for the base asset.
    /// @param crossPrice Initial cross price for the base asset.
    function addBaseAsset(address baseAsset, address vault, uint256 buyPrice, uint256 sellPrice, uint256 crossPrice)
        external
        onlyOwner
    {
        require(baseAsset != address(0), "ARM: invalid asset");
        require(vault != address(0), "ARM: invalid vault");
        require(!baseAssetConfigs[baseAsset].supported, "ARM: asset already supported");
        require(IERC20(baseAsset).decimals() == liquidityAssetDecimals, "ARM: invalid asset decimals");
        require(IAsyncRedeemVault(vault).asset() == liquidityAsset, "ARM: invalid vault asset");
        require(crossPrice >= PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, "ARM: cross price too low");
        require(crossPrice <= PRICE_SCALE, "ARM: cross price too high");
        require(sellPrice >= crossPrice, "ARM: sell price too low");
        require(buyPrice < crossPrice, "ARM: buy price too high");

        supportedBaseAssets.push(baseAsset);
        supportedBaseAssetIndex[baseAsset] = supportedBaseAssets.length;
        baseAssetConfigs[baseAsset] = BaseAssetConfig({
            supported: true,
            vault: vault,
            buyPrice: buyPrice,
            sellPrice: sellPrice,
            crossPrice: crossPrice,
            requestedVaultShares: 0
        });

        emit BaseAssetAdded(baseAsset, vault, buyPrice, sellPrice, crossPrice);
    }

    /// @notice Removes a supported base asset once the ARM no longer holds meaningful exposure to it.
    /// @param baseAsset Base asset to remove.
    function removeBaseAsset(address baseAsset) external onlyOwner {
        BaseAssetConfig memory config = baseAssetConfigs[baseAsset];
        require(config.supported, "ARM: unsupported asset");
        require(IERC20(baseAsset).balanceOf(address(this)) < MIN_TOTAL_SUPPLY, "ARM: too many base assets");
        require(config.requestedVaultShares == 0, "ARM: pending vault redeems");

        uint256 index = supportedBaseAssetIndex[baseAsset] - 1;
        uint256 lastIndex = supportedBaseAssets.length - 1;
        if (index != lastIndex) {
            address lastAsset = supportedBaseAssets[lastIndex];
            supportedBaseAssets[index] = lastAsset;
            supportedBaseAssetIndex[lastAsset] = index + 1;
        }
        supportedBaseAssets.pop();
        delete supportedBaseAssetIndex[baseAsset];
        delete baseAssetConfigs[baseAsset];

        emit BaseAssetRemoved(baseAsset);
    }

    /// @notice Updates the buy and sell prices for a supported base asset.
    /// @param baseAsset Base asset whose prices are being updated.
    /// @param buyPrice New buy price.
    /// @param sellPrice New sell price.
    function setPrices(address baseAsset, uint256 buyPrice, uint256 sellPrice) external onlyOperatorOrOwner {
        BaseAssetConfig storage config = baseAssetConfigs[baseAsset];
        require(config.supported, "ARM: unsupported asset");
        require(sellPrice >= config.crossPrice, "ARM: sell price too low");
        require(buyPrice < config.crossPrice, "ARM: buy price too high");

        config.buyPrice = buyPrice;
        config.sellPrice = sellPrice;

        emit PricesUpdated(baseAsset, buyPrice, sellPrice);
    }

    /// @notice Updates the cross price for a supported base asset.
    /// @param baseAsset Base asset whose cross price is being updated.
    /// @param newCrossPrice New cross price.
    function setCrossPrice(address baseAsset, uint256 newCrossPrice) external onlyOwner {
        BaseAssetConfig storage config = baseAssetConfigs[baseAsset];
        require(config.supported, "ARM: unsupported asset");
        require(newCrossPrice >= PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, "ARM: cross price too low");
        require(newCrossPrice <= PRICE_SCALE, "ARM: cross price too high");
        require(config.sellPrice >= newCrossPrice, "ARM: sell price too low");
        require(config.buyPrice < newCrossPrice, "ARM: buy price too high");

        if (newCrossPrice < config.crossPrice) {
            require(IERC20(baseAsset).balanceOf(address(this)) < MIN_TOTAL_SUPPLY, "ARM: too many base assets");
        }

        config.crossPrice = newCrossPrice;
        emit CrossPriceUpdated(baseAsset, newCrossPrice);
    }

    /// @notice Requests async redemption of base asset vault shares into the liquidity asset.
    /// @param baseAsset Base asset whose vault shares will be redeemed.
    /// @param shares Amount of vault shares to request for redemption.
    function requestVaultRedeem(address baseAsset, uint256 shares) external onlyOperatorOrOwner {
        BaseAssetConfig storage config = baseAssetConfigs[baseAsset];
        require(config.supported, "ARM: unsupported asset");
        IAsyncRedeemVault(config.vault).requestRedeem(shares, address(this), address(this));
        config.requestedVaultShares += shares;

        emit VaultRedeemRequested(baseAsset, config.vault, shares);
    }

    /// @notice Claims previously requested async vault redemptions back into liquidity.
    /// @param baseAsset Base asset whose vault request is being claimed.
    /// @param shares Amount of requested shares to redeem.
    /// @return assets Liquidity asset amount received from the vault.
    function claimVaultRedeem(address baseAsset, uint256 shares) external onlyOperatorOrOwner returns (uint256 assets) {
        BaseAssetConfig storage config = baseAssetConfigs[baseAsset];
        require(config.supported, "ARM: unsupported asset");
        require(shares <= config.requestedVaultShares, "ARM: redeem exceeds requested");
        assets = IAsyncRedeemVault(config.vault).redeem(shares, address(this), address(this));
        config.requestedVaultShares -= shares;

        emit VaultRedeemClaimed(baseAsset, config.vault, shares, assets);
    }

    /// @notice Preview the LP shares that would be minted for a liquidity deposit.
    /// @param assets Liquidity asset amount to deposit.
    /// @return shares LP shares that would be minted.
    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        shares = convertToShares(assets);
    }

    /// @notice Deposits liquidity assets and mints LP shares to the caller.
    /// @param assets Liquidity asset amount to deposit.
    /// @return shares LP shares minted.
    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = _deposit(assets, msg.sender);
    }

    /// @notice Deposits liquidity assets and mints LP shares to a receiver.
    /// @param assets Liquidity asset amount to deposit.
    /// @param receiver Account receiving LP shares.
    /// @return shares LP shares minted.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = _deposit(assets, receiver);
    }

    /// @notice Internal deposit implementation shared by both public deposit methods.
    /// @param assets Liquidity asset amount to deposit.
    /// @param receiver Account receiving LP shares.
    /// @return shares LP shares minted.
    function _deposit(uint256 assets, address receiver) internal returns (uint256 shares) {
        require(totalAssets() > MIN_TOTAL_SUPPLY || withdrawsQueued == withdrawsClaimed, "ARM: insolvent");

        shares = convertToShares(assets);
        lastAvailableAssets += SafeCast.toInt128(SafeCast.toInt256(assets));

        IERC20(liquidityAsset).transferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        if (capManager != address(0)) {
            ICapManager(capManager).postDepositHook(receiver, assets);
        }

        emit Deposit(receiver, assets, shares);
    }

    /// @notice Preview the liquidity assets claimable for a given LP share amount.
    /// @param shares LP shares to redeem.
    /// @return assets Liquidity asset amount represented by the shares.
    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

    /// @notice Burns LP shares and creates a delayed redeem claim for liquidity assets.
    /// @param shares LP shares to burn.
    /// @return requestId Newly created request identifier.
    /// @return assets Liquidity asset amount reserved for the request.
    function requestRedeem(uint256 shares) external returns (uint256 requestId, uint256 assets) {
        assets = convertToAssets(shares);
        requestId = nextWithdrawalIndex;
        nextWithdrawalIndex = requestId + 1;

        uint128 queued = SafeCast.toUint128(withdrawsQueued + assets);
        withdrawsQueued = queued;

        uint40 claimTimestamp = uint40(block.timestamp + claimDelay);

        withdrawalRequests[requestId] = WithdrawalRequest({
            withdrawer: msg.sender,
            claimed: false,
            claimTimestamp: claimTimestamp,
            assets: SafeCast.toUint128(assets),
            queued: queued,
            shares: SafeCast.toUint128(shares)
        });

        _burn(msg.sender, shares);
        lastAvailableAssets -= SafeCast.toInt128(SafeCast.toInt256(assets));

        emit RedeemRequested(msg.sender, requestId, assets, queued, claimTimestamp);
    }

    /// @notice Claims liquidity assets from a previously requested LP redemption.
    /// @param requestId Request identifier to claim.
    /// @return assets Liquidity asset amount transferred to the requester.
    function claimRedeem(uint256 requestId) external returns (uint256 assets) {
        WithdrawalRequest memory request = withdrawalRequests[requestId];

        require(request.claimTimestamp <= block.timestamp, "Claim delay not met");
        require(request.queued <= claimable(), "Queue pending liquidity");
        require(request.withdrawer == msg.sender, "Not requester");
        require(request.claimed == false, "Already claimed");

        uint256 assetsAtClaim = request.shares > 0 ? convertToAssets(request.shares) : request.assets;
        assets = request.assets < assetsAtClaim ? request.assets : assetsAtClaim;

        withdrawalRequests[requestId].claimed = true;
        withdrawsClaimed += SafeCast.toUint128(request.assets);

        address activeMarketMem = activeMarket;
        if (activeMarketMem != address(0)) {
            uint256 liquidityInARM = IERC20(liquidityAsset).balanceOf(address(this));
            if (assets > liquidityInARM) {
                uint256 liquidityFromMarket = assets - liquidityInARM;
                IERC4626(activeMarketMem).withdraw(liquidityFromMarket, address(this), address(this));
            }
        }

        IERC20(liquidityAsset).transfer(msg.sender, assets);
        emit RedeemClaimed(msg.sender, requestId, assets);
    }

    /// @notice Returns the total LP redemption amount currently claimable.
    /// @return claimableAmount Amount of liquidity that can satisfy queued LP claims.
    function claimable() public view returns (uint256 claimableAmount) {
        claimableAmount = withdrawsClaimed + IERC20(liquidityAsset).balanceOf(address(this));

        address activeMarketMem = activeMarket;
        if (activeMarketMem != address(0)) {
            claimableAmount += IERC4626(activeMarketMem).maxWithdraw(address(this));
        }
    }

    /// @notice Ensures enough unreserved liquidity asset remains to satisfy queued LP redeems.
    /// @param amount Additional liquidity asset amount that must remain available.
    function _requireLiquidityAvailable(uint256 amount) internal view {
        uint256 outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;
        if (outstandingWithdrawals == 0) return;

        require(
            amount + outstandingWithdrawals <= IERC20(liquidityAsset).balanceOf(address(this)),
            "ARM: Insufficient liquidity"
        );
    }

    /// @notice Returns total ARM assets net of queued LP redemptions and accrued performance fees.
    /// @return Total net assets expressed in the liquidity asset.
    function totalAssets() public view returns (uint256) {
        (uint256 fees, uint256 newAvailableAssets) = _feesAccrued();
        if (fees + MIN_TOTAL_SUPPLY >= newAvailableAssets) return MIN_TOTAL_SUPPLY;
        return newAvailableAssets - fees;
    }

    /// @notice Returns the shared liquidity asset for ERC-4626-style compatibility.
    /// @return liquidity asset address.
    function asset() external view returns (address) {
        return liquidityAsset;
    }

    /// @notice Calculates available assets before performance fees by valuing all supported positions.
    /// @return availableAssets Gross available assets net of queued LP redemptions.
    /// @return outstandingWithdrawals Liquidity reserved for queued LP redemptions.
    function _availableAssets() internal view returns (uint256 availableAssets, uint256 outstandingWithdrawals) {
        uint256 assets = IERC20(liquidityAsset).balanceOf(address(this));

        uint256 supportedAssetsLength = supportedBaseAssets.length;
        for (uint256 i = 0; i < supportedAssetsLength; ++i) {
            address assetAddr = supportedBaseAssets[i];
            BaseAssetConfig memory config = baseAssetConfigs[assetAddr];
            IAsyncRedeemVault vault = IAsyncRedeemVault(config.vault);

            uint256 onHandAssets = vault.convertToAssets(IERC20(assetAddr).balanceOf(address(this)));
            assets += onHandAssets * config.crossPrice / PRICE_SCALE;
            assets += vault.convertToAssets(config.requestedVaultShares);
        }

        address activeMarketMem = activeMarket;
        if (activeMarketMem != address(0)) {
            uint256 allShares = IERC4626(activeMarketMem).balanceOf(address(this));
            assets += IERC4626(activeMarketMem).previewRedeem(allShares);
        }

        outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;
        if (assets < outstandingWithdrawals) {
            return (0, outstandingWithdrawals);
        }

        availableAssets = assets - outstandingWithdrawals;
    }

    /// @notice Converts a liquidity asset amount into LP shares using current total assets.
    /// @param assets Liquidity asset amount.
    /// @return shares Equivalent LP shares.
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = assets * totalSupply() / totalAssets();
    }

    /// @notice Converts LP shares into liquidity asset units using current total assets.
    /// @param shares LP shares.
    /// @return assetsOut Equivalent liquidity asset amount.
    function convertToAssets(uint256 shares) public view returns (uint256 assetsOut) {
        assetsOut = shares * totalAssets() / totalSupply();
    }

    /// @notice Sets the performance fee rate.
    /// @param _fee New fee in basis points.
    function setFee(uint256 _fee) external onlyOwner {
        _setFee(_fee);
    }

    /// @notice Sets the account that receives performance fees.
    /// @param _feeCollector New fee collector.
    function setFeeCollector(address _feeCollector) external onlyOwner {
        _setFeeCollector(_feeCollector);
    }

    function _setFee(uint256 _fee) internal {
        require(_fee <= FEE_SCALE / 2, "ARM: fee too high");
        collectFees();
        fee = SafeCast.toUint16(_fee);
        emit FeeUpdated(_fee);
    }

    function _setFeeCollector(address _feeCollector) internal {
        require(_feeCollector != address(0), "ARM: invalid fee collector");
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(_feeCollector);
    }

    /// @notice Transfers accrued performance fees to the fee collector.
    /// @return fees Amount of liquidity asset transferred as fees.
    function collectFees() public returns (uint256 fees) {
        uint256 newAvailableAssets;
        (fees, newAvailableAssets) = _feesAccrued();
        lastAvailableAssets = SafeCast.toInt128(SafeCast.toInt256(newAvailableAssets) - SafeCast.toInt256(fees));

        if (fees == 0) return 0;

        _requireLiquidityAvailable(fees);
        require(fees <= IERC20(liquidityAsset).balanceOf(address(this)), "ARM: insufficient liquidity");
        IERC20(liquidityAsset).transfer(feeCollector, fees);

        emit FeeCollected(feeCollector, fees);
    }

    /// @notice Returns currently accrued performance fees without mutating state.
    /// @return fees Amount of accrued fees.
    function feesAccrued() external view returns (uint256 fees) {
        (fees,) = _feesAccrued();
    }

    function _feesAccrued() internal view returns (uint256 fees, uint256 newAvailableAssets) {
        (newAvailableAssets,) = _availableAssets();

        int256 assetIncrease = SafeCast.toInt256(newAvailableAssets) - lastAvailableAssets;
        if (assetIncrease <= 0) return (0, newAvailableAssets);

        fees = SafeCast.toUint256(assetIncrease) * fee / FEE_SCALE;
    }

    /// @notice Adds supported lending markets for the shared liquidity asset.
    /// @param _markets Lending market wrapper addresses to support.
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

    /// @notice Removes a supported lending market that is not currently active.
    /// @param _market Market to remove.
    function removeMarket(address _market) external onlyOwner {
        require(_market != address(0), "ARM: invalid market");
        require(supportedMarkets[_market], "ARM: market not supported");
        require(_market != activeMarket, "ARM: market in active");

        supportedMarkets[_market] = false;
        emit MarketRemoved(_market);
    }

    /// @notice Sets the active lending market and migrates liquidity out of the previous one.
    /// @param _market New active market, or zero address to disable lending allocation.
    function setActiveMarket(address _market) external onlyOperatorOrOwner {
        require(_market == address(0) || supportedMarkets[_market], "ARM: market not supported");
        address previousActiveMarket = activeMarket;
        if (previousActiveMarket == _market) return;

        if (previousActiveMarket != address(0)) {
            uint256 shares = IERC4626(previousActiveMarket).balanceOf(address(this));
            if (shares > 0) {
                IERC4626(previousActiveMarket).redeem(shares, address(this), address(this));
            }
        }

        activeMarket = _market;
        emit ActiveMarketUpdated(_market);

        if (_market == address(0)) return;
        _allocate();
    }

    /// @notice Rebalances liquidity between the ARM and the active lending market.
    /// @return targetLiquidityDelta Desired liquidity movement.
    /// @return actualLiquidityDelta Actual liquidity movement achieved.
    function allocate() external returns (int256 targetLiquidityDelta, int256 actualLiquidityDelta) {
        require(activeMarket != address(0), "ARM: no active market");
        return _allocate();
    }

    function _allocate() internal returns (int256 targetLiquidityDelta, int256 actualLiquidityDelta) {
        (uint256 availableAssets, uint256 outstandingWithdrawals) = _availableAssets();
        if (availableAssets == 0) return (0, 0);

        uint256 targetArmLiquidity = availableAssets * armBuffer / 1e18;
        int256 currentArmLiquidity = SafeCast.toInt256(IERC20(liquidityAsset).balanceOf(address(this)))
            - SafeCast.toInt256(outstandingWithdrawals);

        targetLiquidityDelta = currentArmLiquidity - SafeCast.toInt256(targetArmLiquidity);
        address activeMarketMem = activeMarket;

        if (targetLiquidityDelta > allocateThreshold) {
            uint256 depositAmount = SafeCast.toUint256(targetLiquidityDelta);
            IERC20(liquidityAsset).approve(activeMarketMem, depositAmount);
            IERC4626(activeMarketMem).deposit(depositAmount, address(this));
            actualLiquidityDelta = SafeCast.toInt256(depositAmount);
        } else if (targetLiquidityDelta < 0) {
            uint256 availableMarketAssets = IERC4626(activeMarketMem).maxWithdraw(address(this));
            uint256 desiredWithdrawAmount = SafeCast.toUint256(-targetLiquidityDelta);

            if (availableMarketAssets < desiredWithdrawAmount) {
                uint256 shares = IERC4626(activeMarketMem).maxRedeem(address(this));
                if (shares <= minSharesToRedeem) return (targetLiquidityDelta, 0);
                uint256 redeemedAssets = IERC4626(activeMarketMem).redeem(shares, address(this), address(this));
                actualLiquidityDelta = -SafeCast.toInt256(redeemedAssets);
            } else {
                IERC4626(activeMarketMem).withdraw(desiredWithdrawAmount, address(this), address(this));
                actualLiquidityDelta = -SafeCast.toInt256(desiredWithdrawAmount);
            }
        }

        emit Allocated(activeMarketMem, targetLiquidityDelta, actualLiquidityDelta);
    }

    /// @notice Sets the cap manager used for LP deposit hooks.
    /// @param _capManager New cap manager, or zero to disable.
    function setCapManager(address _capManager) external onlyOwner {
        capManager = _capManager;
        emit CapManagerUpdated(_capManager);
    }

    /// @notice Sets the fraction of available assets to keep on hand in the ARM.
    /// @param _armBuffer New buffer ratio scaled by 1e18.
    function setARMBuffer(uint256 _armBuffer) external onlyOperatorOrOwner {
        require(_armBuffer <= 1e18, "ARM: invalid arm buffer");
        armBuffer = _armBuffer;
        emit ARMBufferUpdated(_armBuffer);
    }

}
