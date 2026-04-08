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
    uint256 public constant MAX_CROSS_PRICE_DEVIATION = 20e32;
    uint256 public constant PRICE_SCALE = 1e36;
    uint256 internal constant MIN_TOTAL_SUPPLY = 1e12;
    address internal constant DEAD_ACCOUNT = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant FEE_SCALE = 10000;

    uint256 public immutable minSharesToRedeem;
    int256 public immutable allocateThreshold;
    address public immutable liquidityAsset;
    uint8 internal immutable liquidityAssetDecimals;
    uint256 public immutable claimDelay;

    struct BaseAssetConfig {
        bool supported;
        address vault;
        uint256 buyPrice;
        uint256 sellPrice;
        uint256 crossPrice;
        uint256 requestedVaultShares;
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
    int128 public lastAvailableAssets;
    address public feeCollector;
    address public capManager;

    address public activeMarket;
    mapping(address market => bool supported) public supportedMarkets;
    uint256 public armBuffer;

    address[] internal supportedBaseAssets;
    mapping(address asset => BaseAssetConfig) internal baseAssetConfigs;
    mapping(address asset => uint256 indexPlusOne) internal supportedBaseAssetIndex;

    uint256[34] private _gap;

    event BaseAssetAdded(address indexed asset, address indexed vault, uint256 buyPrice, uint256 sellPrice, uint256 crossPrice);
    event BaseAssetRemoved(address indexed asset);
    event PricesUpdated(address indexed asset, uint256 buyPrice, uint256 sellPrice);
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
    event VaultRedeemRequested(address indexed asset, address indexed vault, uint256 shares);
    event VaultRedeemClaimed(address indexed asset, address indexed vault, uint256 shares, uint256 assets);

    constructor(address _liquidityAsset, uint256 _claimDelay, uint256 _minSharesToRedeem, int256 _allocateThreshold) {
        liquidityAsset = _liquidityAsset;
        liquidityAssetDecimals = IERC20(_liquidityAsset).decimals();
        claimDelay = _claimDelay;

        _setOwner(address(0));

        require(_allocateThreshold >= 0, "invalid allocate threshold");
        allocateThreshold = _allocateThreshold;
        minSharesToRedeem = _minSharesToRedeem;
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

        (uint256 availableAssets,) = _availableAssets();
        lastAvailableAssets = SafeCast.toInt128(SafeCast.toInt256(availableAssets));
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
    ) external returns (uint256[] memory amounts) {
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
        if (inToken == liquidityAsset && isSupportedBaseAsset(outToken)) {
            return (outToken, true);
        }
        if (outToken == liquidityAsset && isSupportedBaseAsset(inToken)) {
            return (inToken, false);
        }
        revert("ARM: Invalid swap assets");
    }

    function getReserves(address baseAsset) external view returns (uint256 liquidityReserve, uint256 baseReserve) {
        require(isSupportedBaseAsset(baseAsset), "ARM: unsupported asset");

        uint256 outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;
        uint256 liquidityBalance = IERC20(liquidityAsset).balanceOf(address(this));
        liquidityReserve = outstandingWithdrawals > liquidityBalance ? 0 : liquidityBalance - outstandingWithdrawals;
        baseReserve = IERC20(baseAsset).balanceOf(address(this));
    }

    function isSupportedBaseAsset(address baseAsset) public view returns (bool) {
        return baseAssetConfigs[baseAsset].supported;
    }

    function getSupportedBaseAssets() external view returns (address[] memory) {
        return supportedBaseAssets;
    }

    function getBaseAssetConfig(address baseAsset) external view returns (BaseAssetConfig memory) {
        return baseAssetConfigs[baseAsset];
    }

    function getPrices(address baseAsset) external view returns (uint256 buyPrice, uint256 sellPrice) {
        BaseAssetConfig memory config = _requireSupportedBaseAsset(baseAsset);
        return (config.buyPrice, config.sellPrice);
    }

    function addBaseAsset(address baseAsset, address vault, uint256 buyPrice, uint256 sellPrice, uint256 crossPrice)
        external
        onlyOwner
    {
        require(baseAsset != address(0), "ARM: invalid asset");
        require(vault != address(0), "ARM: invalid vault");
        require(!isSupportedBaseAsset(baseAsset), "ARM: asset already supported");
        require(IERC20(baseAsset).decimals() == liquidityAssetDecimals, "ARM: invalid asset decimals");
        require(IAsyncRedeemVault(vault).asset() == liquidityAsset, "ARM: invalid vault asset");

        _validatePrices(buyPrice, sellPrice, crossPrice);

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

    function removeBaseAsset(address baseAsset) external onlyOwner {
        BaseAssetConfig memory config = _requireSupportedBaseAsset(baseAsset);
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

    function setPrices(address baseAsset, uint256 buyPrice, uint256 sellPrice) external onlyOperatorOrOwner {
        BaseAssetConfig storage config = _requireSupportedBaseAssetStorage(baseAsset);
        require(sellPrice >= config.crossPrice, "ARM: sell price too low");
        require(buyPrice < config.crossPrice, "ARM: buy price too high");

        config.buyPrice = buyPrice;
        config.sellPrice = sellPrice;

        emit PricesUpdated(baseAsset, buyPrice, sellPrice);
    }

    function setCrossPrice(address baseAsset, uint256 newCrossPrice) external onlyOwner {
        BaseAssetConfig storage config = _requireSupportedBaseAssetStorage(baseAsset);
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

    function requestVaultRedeem(address baseAsset, uint256 shares) external onlyOperatorOrOwner {
        BaseAssetConfig storage config = _requireSupportedBaseAssetStorage(baseAsset);
        IAsyncRedeemVault(config.vault).requestRedeem(shares, address(this), address(this));
        config.requestedVaultShares += shares;

        emit VaultRedeemRequested(baseAsset, config.vault, shares);
    }

    function claimVaultRedeem(address baseAsset, uint256 shares) external onlyOperatorOrOwner returns (uint256 assets) {
        BaseAssetConfig storage config = _requireSupportedBaseAssetStorage(baseAsset);
        require(shares <= config.requestedVaultShares, "ARM: redeem exceeds requested");
        assets = IAsyncRedeemVault(config.vault).redeem(shares, address(this), address(this));
        config.requestedVaultShares -= shares;

        emit VaultRedeemClaimed(baseAsset, config.vault, shares, assets);
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
        lastAvailableAssets += SafeCast.toInt128(SafeCast.toInt256(assets));

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
        lastAvailableAssets -= SafeCast.toInt128(SafeCast.toInt256(assets));

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
                uint256 liquidityFromMarket = assets - liquidityInARM;
                IERC4626(activeMarketMem).withdraw(liquidityFromMarket, address(this), address(this));
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

    function totalAssets() public view returns (uint256) {
        (uint256 fees, uint256 newAvailableAssets) = _feesAccrued();
        if (fees + MIN_TOTAL_SUPPLY >= newAvailableAssets) return MIN_TOTAL_SUPPLY;
        return newAvailableAssets - fees;
    }

    function asset() external view returns (address) {
        return liquidityAsset;
    }

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

    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = assets * totalSupply() / totalAssets();
    }

    function convertToAssets(uint256 shares) public view returns (uint256 assetsOut) {
        assetsOut = shares * totalAssets() / totalSupply();
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
        uint256 newAvailableAssets;
        (fees, newAvailableAssets) = _feesAccrued();
        lastAvailableAssets = SafeCast.toInt128(SafeCast.toInt256(newAvailableAssets) - SafeCast.toInt256(fees));

        if (fees == 0) return 0;

        _requireLiquidityAvailable(fees);
        require(fees <= IERC20(liquidityAsset).balanceOf(address(this)), "ARM: insufficient liquidity");
        IERC20(liquidityAsset).transfer(feeCollector, fees);

        emit FeeCollected(feeCollector, fees);
    }

    function feesAccrued() external view returns (uint256 fees) {
        (fees,) = _feesAccrued();
    }

    function _feesAccrued() internal view returns (uint256 fees, uint256 newAvailableAssets) {
        (newAvailableAssets,) = _availableAssets();

        int256 assetIncrease = SafeCast.toInt256(newAvailableAssets) - lastAvailableAssets;
        if (assetIncrease <= 0) return (0, newAvailableAssets);

        fees = SafeCast.toUint256(assetIncrease) * fee / FEE_SCALE;
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

    function _requireSupportedBaseAsset(address baseAsset) internal view returns (BaseAssetConfig memory config) {
        config = baseAssetConfigs[baseAsset];
        require(config.supported, "ARM: unsupported asset");
    }

    function _requireSupportedBaseAssetStorage(address baseAsset) internal view returns (BaseAssetConfig storage config) {
        config = baseAssetConfigs[baseAsset];
        require(config.supported, "ARM: unsupported asset");
    }

    function _validatePrices(uint256 buyPrice, uint256 sellPrice, uint256 crossPrice) internal pure {
        require(crossPrice >= PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, "ARM: cross price too low");
        require(crossPrice <= PRICE_SCALE, "ARM: cross price too high");
        require(sellPrice >= crossPrice, "ARM: sell price too low");
        require(buyPrice < crossPrice, "ARM: buy price too high");
    }
}
