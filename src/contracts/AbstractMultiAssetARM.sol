// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {OwnableOperable} from "./OwnableOperable.sol";
import {IAssetAdapter, IERC20, ICapManager} from "./Interfaces.sol";

/**
 * @title Reusable multi-base Automated Redemption Manager (ARM)
 * @author Origin Protocol Inc
 */
abstract contract AbstractMultiAssetARM is OwnableOperable, ERC20Upgradeable {
    uint256 public constant MAX_CROSS_PRICE_DEVIATION = 20e32;
    uint256 public constant PRICE_SCALE = 1e36;
    uint256 internal constant MIN_TOTAL_SUPPLY = 1e12;
    address internal constant DEAD_ACCOUNT = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant FEE_SCALE = 10000;

    uint256 public immutable minSharesToRedeem;
    int256 public immutable allocateThreshold;
    address public immutable liquidityAsset;
    uint256 public immutable claimDelay;

    struct BaseAssetConfig {
        uint128 buyPrice;
        uint128 sellPrice;
        uint128 buyLiquidityRemaining;
        uint128 sellLiquidityRemaining;
        uint128 crossPrice;
        uint120 pendingRedeemAssets;
        bool peggedToLiquidityAsset;
        address adapter;
    }

    uint128 public withdrawsQueued;
    uint128 public withdrawsClaimed;
    uint256 public nextWithdrawalIndex;

    struct WithdrawalRequest {
        address withdrawer;
        bool claimed;
        uint40 claimTimestamp;
        uint128 assets;
        uint128 queued;
        uint128 shares;
    }

    mapping(uint256 requestId => WithdrawalRequest) public withdrawalRequests;

    uint16 public fee;
    int128 internal _deprecatedLastAvailableAssets;
    address public feeCollector;
    address public capManager;

    address public activeMarket;
    mapping(address market => bool supported) public supportedMarkets;
    uint256 public armBuffer;
    uint128 internal _deprecatedSwapFeeMultiplier;
    uint128 public feesAccrued;

    address[] internal baseAssets;
    mapping(address asset => BaseAssetConfig) public baseAssetConfigs;

    uint256[33] private _gap;

    event BaseAssetAdded(
        address indexed asset,
        address indexed adapter,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 crossPrice,
        bool peggedToLiquidityAsset
    );
    event BaseAssetRemoved(address indexed asset);
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

    constructor(address _liquidityAsset, uint256 _claimDelay, uint256 _minSharesToRedeem, int256 _allocateThreshold) {
        liquidityAsset = _liquidityAsset;
        claimDelay = _claimDelay;
        minSharesToRedeem = _minSharesToRedeem;

        require(_allocateThreshold >= 0, "invalid allocate threshold");
        allocateThreshold = _allocateThreshold;

        _setOwner(address(0));
    }

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

        _setFee(_fee);
        _setFeeCollector(_feeCollector);

        capManager = _capManager;
        emit CapManagerUpdated(_capManager);
    }

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

    function _inDeadline(uint256 deadline) internal view {
        require(deadline >= block.timestamp, "ARM: Deadline expired");
    }

    function _ensureLiquidityAvailableForSwap(uint256 amount) internal {
        uint256 liquidityBalance = IERC20(liquidityAsset).balanceOf(address(this));
        uint256 outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;
        uint256 requiredLiquidity = amount + outstandingWithdrawals;

        if (requiredLiquidity <= liquidityBalance) return;

        address activeMarketMem = activeMarket;
        require(activeMarketMem != address(0), "ARM: Insufficient liquidity");

        uint256 shortfall = requiredLiquidity - liquidityBalance;
        try IERC4626(activeMarketMem).withdraw(shortfall, address(this), address(this)) {}
        catch {
            revert("ARM: Insufficient liquidity");
        }
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, address to)
        internal
        returns (uint256 amountOut)
    {
        (address baseAsset, bool inIsLiquidity) = _getSwapBaseAsset(address(inToken), address(outToken));
        BaseAssetConfig storage config = baseAssetConfigs[baseAsset];

        bool isBuySide;
        if (inIsLiquidity) {
            uint256 convertedAmountIn = _convertToShares(config, amountIn);
            amountOut = convertedAmountIn * PRICE_SCALE / config.sellPrice;
            _consumeSwapLiquidityLimit(config, false, amountOut);
        } else {
            uint256 convertedAmountIn = _convertToAssets(config, amountIn);
            amountOut = convertedAmountIn * config.buyPrice / PRICE_SCALE;
            isBuySide = true;
            _consumeSwapLiquidityLimit(config, true, amountOut);
            _accrueSwapFee(config.buyPrice, amountOut);
            _ensureLiquidityAvailableForSwap(amountOut);
        }

        inToken.transferFrom(msg.sender, address(this), amountIn);
        outToken.transfer(to, amountOut);

        isBuySide;
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountOut, address to)
        internal
        returns (uint256 amountIn)
    {
        (address baseAsset, bool inIsLiquidity) = _getSwapBaseAsset(address(inToken), address(outToken));
        BaseAssetConfig storage config = baseAssetConfigs[baseAsset];

        if (inIsLiquidity) {
            uint256 convertedAmountOut = _convertToAssets(config, amountOut);
            amountIn = convertedAmountOut * config.sellPrice / PRICE_SCALE + 3;
            _consumeSwapLiquidityLimit(config, false, amountOut);
        } else {
            uint256 convertedAmountOut = _convertToShares(config, amountOut);
            amountIn = convertedAmountOut * PRICE_SCALE / config.buyPrice + 3;
            _consumeSwapLiquidityLimit(config, true, amountOut);
            _accrueSwapFee(config.buyPrice, amountOut);
            _ensureLiquidityAvailableForSwap(amountOut);
        }

        inToken.transferFrom(msg.sender, address(this), amountIn);
        outToken.transfer(to, amountOut);
    }

    function _getSwapBaseAsset(address inToken, address outToken)
        internal
        view
        returns (address baseAsset, bool inIsLiquidity)
    {
        if (inToken == liquidityAsset && baseAssetConfigs[outToken].adapter != address(0)) {
            return (outToken, true);
        }
        if (outToken == liquidityAsset && baseAssetConfigs[inToken].adapter != address(0)) {
            return (inToken, false);
        }
        revert("ARM: Invalid swap assets");
    }

    function _consumeSwapLiquidityLimit(BaseAssetConfig storage config, bool isBuySide, uint256 amountOut) internal {
        uint256 remaining = isBuySide ? config.buyLiquidityRemaining : config.sellLiquidityRemaining;
        require(amountOut <= remaining, "ARM: Insufficient liquidity");
        if (remaining == type(uint128).max) return;

        remaining -= amountOut;
        if (isBuySide) config.buyLiquidityRemaining = SafeCast.toUint128(remaining);
        else config.sellLiquidityRemaining = SafeCast.toUint128(remaining);
    }

    function _convertToAssets(BaseAssetConfig memory config, uint256 shares) internal view returns (uint256 assets) {
        if (config.peggedToLiquidityAsset) return shares;
        return IAssetAdapter(config.adapter).convertToAssets(shares);
    }

    function _convertToShares(BaseAssetConfig memory config, uint256 assets) internal view returns (uint256 shares) {
        if (config.peggedToLiquidityAsset) return assets;
        return IAssetAdapter(config.adapter).convertToShares(assets);
    }

    function _accrueSwapFee(uint256 buyPrice, uint256 amountOut) internal {
        uint256 feeMultiplier =
            buyPrice == 0 ? 0 : (PRICE_SCALE - buyPrice) * uint256(fee) * PRICE_SCALE / (buyPrice * FEE_SCALE);
        feesAccrued = SafeCast.toUint128(feesAccrued + amountOut * feeMultiplier / PRICE_SCALE);
    }

    function addBaseAsset(
        address baseAsset,
        address adapter,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 buyAmount,
        uint256 sellAmount,
        uint256 crossPrice,
        bool peggedToLiquidityAsset
    ) external onlyOwner {
        require(baseAsset != address(0), "ARM: invalid asset");
        require(adapter != address(0), "ARM: invalid adapter");
        require(baseAssetConfigs[baseAsset].adapter == address(0), "ARM: asset already supported");
        require(IAssetAdapter(adapter).asset() == liquidityAsset, "ARM: invalid adapter asset");
        require(crossPrice >= PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, "ARM: cross price too low");
        require(crossPrice <= PRICE_SCALE, "ARM: cross price too high");
        require(sellPrice >= crossPrice, "ARM: sell price too low");
        require(buyPrice < crossPrice, "ARM: buy price too high");

        baseAssets.push(baseAsset);
        IERC20(baseAsset).approve(adapter, type(uint256).max);
        baseAssetConfigs[baseAsset] = BaseAssetConfig({
            buyPrice: SafeCast.toUint128(buyPrice),
            sellPrice: SafeCast.toUint128(sellPrice),
            buyLiquidityRemaining: _toUint128Max(buyAmount),
            sellLiquidityRemaining: _toUint128Max(sellAmount),
            crossPrice: SafeCast.toUint128(crossPrice),
            pendingRedeemAssets: 0,
            peggedToLiquidityAsset: peggedToLiquidityAsset,
            adapter: adapter
        });

        emit BaseAssetAdded(baseAsset, adapter, buyPrice, sellPrice, crossPrice, peggedToLiquidityAsset);
    }

    function removeBaseAsset(address baseAsset) external onlyOwner {
        BaseAssetConfig memory config = baseAssetConfigs[baseAsset];
        require(config.adapter != address(0), "ARM: unsupported asset");
        require(IERC20(baseAsset).balanceOf(address(this)) < MIN_TOTAL_SUPPLY, "ARM: too many base assets");
        require(config.pendingRedeemAssets == 0, "ARM: pending redeems");

        uint256 length = baseAssets.length;
        for (uint256 i = 0; i < length; ++i) {
            if (baseAssets[i] == baseAsset) {
                baseAssets[i] = baseAssets[length - 1];
                baseAssets.pop();
                delete baseAssetConfigs[baseAsset];
                emit BaseAssetRemoved(baseAsset);
                return;
            }
        }

        revert("ARM: asset not found");
    }

    function setPrices(address baseAsset, uint256 buyPrice, uint256 sellPrice, uint256 buyAmount, uint256 sellAmount)
        external
        onlyOperatorOrOwner
    {
        BaseAssetConfig storage config = baseAssetConfigs[baseAsset];
        require(config.adapter != address(0), "ARM: unsupported asset");
        require(sellPrice >= config.crossPrice, "ARM: sell price too low");
        require(buyPrice < config.crossPrice, "ARM: buy price too high");

        config.buyPrice = SafeCast.toUint128(buyPrice);
        config.sellPrice = SafeCast.toUint128(sellPrice);
        config.buyLiquidityRemaining = _toUint128Max(buyAmount);
        config.sellLiquidityRemaining = _toUint128Max(sellAmount);

        emit TraderateChanged(baseAsset, buyPrice, sellPrice);
    }

    function setCrossPrice(address baseAsset, uint256 newCrossPrice) external onlyOwner {
        BaseAssetConfig storage config = baseAssetConfigs[baseAsset];
        require(config.adapter != address(0), "ARM: unsupported asset");
        require(newCrossPrice >= PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, "ARM: cross price too low");
        require(newCrossPrice <= PRICE_SCALE, "ARM: cross price too high");
        require(config.sellPrice >= newCrossPrice, "ARM: sell price too low");
        require(config.buyPrice < newCrossPrice, "ARM: buy price too high");

        if (newCrossPrice < config.crossPrice) {
            require(IERC20(baseAsset).balanceOf(address(this)) < MIN_TOTAL_SUPPLY, "ARM: too many base assets");
        }

        config.crossPrice = SafeCast.toUint128(newCrossPrice);
        emit CrossPriceUpdated(baseAsset, newCrossPrice);
    }

    function requestRedeem(address baseAsset, uint256 shares)
        external
        onlyOperatorOrOwner
        returns (uint256 sharesRequested, uint256 assetsExpected)
    {
        BaseAssetConfig storage config = baseAssetConfigs[baseAsset];
        require(config.adapter != address(0), "ARM: unsupported asset");

        (sharesRequested, assetsExpected) = IAssetAdapter(config.adapter).requestRedeem(shares);
        config.pendingRedeemAssets = SafeCast.toUint120(uint256(config.pendingRedeemAssets) + assetsExpected);
    }

    function claimRedeem(address baseAsset, uint256 shares)
        external
        onlyOperatorOrOwner
        returns (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived)
    {
        BaseAssetConfig storage config = baseAssetConfigs[baseAsset];
        require(config.adapter != address(0), "ARM: unsupported asset");

        (sharesClaimed, assetsExpected, assetsReceived) = IAssetAdapter(config.adapter).redeem(shares);
        config.pendingRedeemAssets = SafeCast.toUint120(uint256(config.pendingRedeemAssets) - assetsExpected);
    }

    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        shares = convertToShares(assets);
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = _deposit(assets, msg.sender);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = _deposit(assets, receiver);
    }

    function _deposit(uint256 assets, address receiver) internal returns (uint256 shares) {
        require(totalAssets() > MIN_TOTAL_SUPPLY || withdrawsQueued == withdrawsClaimed, "ARM: insolvent");
        shares = convertToShares(assets);

        IERC20(liquidityAsset).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);

        if (capManager != address(0)) {
            ICapManager(capManager).postDepositHook(receiver, assets);
        }

        emit Deposit(receiver, assets, shares);
    }

    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

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
        emit RedeemRequested(msg.sender, requestId, assets, queued, claimTimestamp);
    }

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
                IERC4626(activeMarketMem).withdraw(assets - liquidityInARM, address(this), address(this));
            }
        }

        IERC20(liquidityAsset).transfer(msg.sender, assets);
        emit RedeemClaimed(msg.sender, requestId, assets);
    }

    function claimable() public view returns (uint256 claimableAmount) {
        claimableAmount = withdrawsClaimed + IERC20(liquidityAsset).balanceOf(address(this));

        address activeMarketMem = activeMarket;
        if (activeMarketMem != address(0)) {
            claimableAmount += IERC4626(activeMarketMem).maxWithdraw(address(this));
        }
    }

    function _requireLiquidityAvailable(uint256 amount) internal view {
        uint256 outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;
        if (outstandingWithdrawals == 0) return;

        require(
            amount + outstandingWithdrawals <= IERC20(liquidityAsset).balanceOf(address(this)),
            "ARM: Insufficient liquidity"
        );
    }

    function totalAssets() public view virtual returns (uint256) {
        (uint256 newAvailableAssets,) = _availableAssets();
        uint256 feesAccruedMem = feesAccrued;
        if (feesAccruedMem + MIN_TOTAL_SUPPLY >= newAvailableAssets) return MIN_TOTAL_SUPPLY;
        return newAvailableAssets - feesAccruedMem;
    }

    function asset() external view virtual returns (address) {
        return liquidityAsset;
    }

    function _availableAssets() internal view returns (uint256 availableAssets, uint256 outstandingWithdrawals) {
        uint256 assets = IERC20(liquidityAsset).balanceOf(address(this));

        uint256 length = baseAssets.length;
        for (uint256 i = 0; i < length; ++i) {
            address baseAsset = baseAssets[i];
            BaseAssetConfig memory config = baseAssetConfigs[baseAsset];
            uint256 baseConvertedToLiquid = _convertToAssets(config, IERC20(baseAsset).balanceOf(address(this)));
            assets += baseConvertedToLiquid * config.crossPrice / PRICE_SCALE;
            assets += config.pendingRedeemAssets;
        }

        address activeMarketMem = activeMarket;
        if (activeMarketMem != address(0)) {
            uint256 allShares = IERC4626(activeMarketMem).balanceOf(address(this));
            assets += IERC4626(activeMarketMem).convertToAssets(allShares);
        }

        outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;
        if (assets < outstandingWithdrawals) return (0, outstandingWithdrawals);

        availableAssets = assets - outstandingWithdrawals;
    }

    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = assets * totalSupply() / totalAssets();
    }

    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = shares * totalAssets() / totalSupply();
    }

    function setFee(uint256 _fee) external onlyOwner {
        _setFee(_fee);
    }

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

    function collectFees() public returns (uint256 fees) {
        fees = feesAccrued;
        if (fees == 0) return 0;

        _requireLiquidityAvailable(fees);
        require(fees <= IERC20(liquidityAsset).balanceOf(address(this)), "ARM: insufficient liquidity");

        feesAccrued = 0;
        IERC20(liquidityAsset).transfer(feeCollector, fees);

        emit FeeCollected(feeCollector, fees);
    }

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

    function removeMarket(address _market) external onlyOwner {
        require(_market != address(0), "ARM: invalid market");
        require(supportedMarkets[_market], "ARM: market not supported");
        require(_market != activeMarket, "ARM: market in active");

        supportedMarkets[_market] = false;
        emit MarketRemoved(_market);
    }

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

    function setCapManager(address _capManager) external onlyOwner {
        capManager = _capManager;
        emit CapManagerUpdated(_capManager);
    }

    function setARMBuffer(uint256 _armBuffer) external onlyOperatorOrOwner {
        require(_armBuffer <= 1e18, "ARM: invalid arm buffer");
        armBuffer = _armBuffer;
        emit ARMBufferUpdated(_armBuffer);
    }

    function _toUint128Max(uint256 amount) internal pure returns (uint128) {
        if (amount == type(uint256).max) return type(uint128).max;
        return SafeCast.toUint128(amount);
    }
}
