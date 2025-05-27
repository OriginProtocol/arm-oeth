// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {OwnableOperable} from "./OwnableOperable.sol";
import {IERC20, ICapManager} from "./Interfaces.sol";

/**
 * @title Generic Automated Redemption Manager (ARM)
 * @author Origin Protocol Inc
 */
abstract contract AbstractARM is OwnableOperable, ERC20Upgradeable {
    ////////////////////////////////////////////////////
    ///                 Constants
    ////////////////////////////////////////////////////

    /// @notice Maximum amount the Owner can set the cross price below 1 scaled to 36 decimals.
    /// 20e32 is a 0.2% deviation, or 20 basis points.
    uint256 public constant MAX_CROSS_PRICE_DEVIATION = 20e32;
    /// @notice Scale of the prices.
    uint256 public constant PRICE_SCALE = 1e36;
    /// @dev The amount of shares that are minted to a dead address on initialization
    uint256 internal constant MIN_TOTAL_SUPPLY = 1e12;
    /// @dev The address with no known private key that the initial shares are minted to
    address internal constant DEAD_ACCOUNT = 0x000000000000000000000000000000000000dEaD;
    /// @notice The scale of the performance fee
    /// 10,000 = 100% performance fee
    uint256 public constant FEE_SCALE = 10000;

    ////////////////////////////////////////////////////
    ///             Immutable Variables
    ////////////////////////////////////////////////////
    /// @dev The minimum amount of shares that can be redeemed from the active market.
    uint256 public immutable minSharesToRedeem;
    /// @notice The address of the asset that is used to add and remove liquidity. eg WETH
    /// This is also the quote asset when the prices are set.
    /// eg the stETH/WETH price has a base asset of stETH and quote asset of WETH.
    address public immutable liquidityAsset;
    /// @notice The asset being purchased by the ARM and put in the withdrawal queue. eg stETH
    address public immutable baseAsset;
    /// @notice The swap input token that is transferred to this contract.
    /// From a User perspective, this is the token being sold.
    /// token0 is also compatible with the Uniswap V2 Router interface.
    IERC20 public immutable token0;
    /// @notice The swap output token that is transferred from this contract.
    /// From a User perspective, this is the token being bought.
    /// token1 is also compatible with the Uniswap V2 Router interface.
    IERC20 public immutable token1;
    /// @notice The delay before a withdrawal request can be claimed in seconds. eg 600 is 10 minutes.
    uint256 public immutable claimDelay;

    ////////////////////////////////////////////////////
    ///             Storage Variables
    ////////////////////////////////////////////////////

    /**
     * @notice For one `token0` from a Trader, how many `token1` does the pool send.
     * For example, if `token0` is WETH and `token1` is stETH then
     * `traderate0` is the WETH/stETH price.
     * From a Trader's perspective, this is the buy price.
     * From the ARM's perspective, this is the sell price.
     * Rate is to 36 decimals (1e36).
     * To convert to a stETH/WETH price, use `PRICE_SCALE * PRICE_SCALE / traderate0`.
     */
    uint256 public traderate0;
    /**
     * @notice For one `token1` from a Trader, how many `token0` does the pool send.
     * For example, if `token0` is WETH and `token1` is stETH then
     * `traderate1` is the stETH/WETH price.
     * From a Trader's perspective, this is the sell price.
     * From a ARM's perspective, this is the buy price.
     * Rate is to 36 decimals (1e36).
     */
    uint256 public traderate1;
    /// @notice The price that buy and sell prices can not cross scaled to 36 decimals.
    /// This is also the price the base assets, eg stETH, in the ARM contract are priced at in `totalAssets`.
    uint256 public crossPrice;

    /// @notice Cumulative total of all withdrawal requests including the ones that have already been claimed.
    uint128 public withdrawsQueued;
    /// @notice Total of all the withdrawal requests that have been claimed.
    uint128 public withdrawsClaimed;
    /// @notice Index of the next withdrawal request starting at 0.
    uint256 public nextWithdrawalIndex;

    struct WithdrawalRequest {
        address withdrawer;
        bool claimed;
        // When the withdrawal can be claimed
        uint40 claimTimestamp;
        // Amount of liquidity assets to withdraw. eg WETH
        uint128 assets;
        // Cumulative total of all withdrawal requests including this one when the redeem request was made.
        uint128 queued;
    }

    /// @notice Mapping of withdrawal request indices to the user withdrawal request data.
    mapping(uint256 requestId => WithdrawalRequest) public withdrawalRequests;

    /// @notice Performance fee that is collected by the feeCollector measured in basis points (1/100th of a percent).
    /// 10,000 = 100% performance fee
    /// 2,000 = 20% performance fee
    /// 500 = 5% performance fee
    uint16 public fee;
    /// @notice The available assets the last time the performance fees were collected and adjusted
    /// for liquidity assets (WETH) deposited and redeemed.
    /// This can be negative if there were asset gains and then all the liquidity providers redeemed.
    int128 public lastAvailableAssets;
    /// @notice The account or contract that can collect the performance fee.
    address public feeCollector;
    /// @notice The address of the CapManager contract used to manage the ARM's liquidity provider and total assets caps.
    address public capManager;

    /// @notice The address of the active lending market.
    address public activeMarket;
    /// @notice Lending markets that can be used by the ARM.
    mapping(address market => bool supported) public supportedMarkets;
    /// @notice Percentage of liquid assets to keep in the ARM. 100% = 1e18.
    uint256 public armBuffer;

    uint256[38] private _gap;

    ////////////////////////////////////////////////////
    ///                 Events
    ////////////////////////////////////////////////////

    event TraderateChanged(uint256 traderate0, uint256 traderate1);
    event CrossPriceUpdated(uint256 crossPrice);
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
    event Allocated(address indexed market, int256 assets);

    constructor(
        address _token0,
        address _token1,
        address _liquidityAsset,
        uint256 _claimDelay,
        uint256 _minSharesToRedeem
    ) {
        require(IERC20(_token0).decimals() == 18);
        require(IERC20(_token1).decimals() == 18);

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        claimDelay = _claimDelay;

        _setOwner(address(0)); // Revoke owner for implementation contract at deployment

        require(_liquidityAsset == address(token0) || _liquidityAsset == address(token1), "invalid liquidity asset");
        liquidityAsset = _liquidityAsset;
        // The base asset, eg stETH, is not the liquidity asset, eg WETH
        baseAsset = _liquidityAsset == _token0 ? _token1 : _token0;
        minSharesToRedeem = _minSharesToRedeem;
    }

    /// @notice Initialize the contract.
    /// The deployer that calls initialize has to approve the this ARM's proxy contract to transfer 1e12 WETH.
    /// @param _operator The address of the account that can request and claim Lido withdrawals.
    /// @param _name The name of the liquidity provider (LP) token.
    /// @param _symbol The symbol of the liquidity provider (LP) token.
    /// @param _fee The performance fee that is collected by the feeCollector measured in basis points (1/100th of a percent).
    /// 10,000 = 100% performance fee
    /// 500 = 5% performance fee
    /// @param _feeCollector The account that can collect the performance fee
    /// @param _capManager The address of the CapManager contract
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

        // Transfer a small bit of liquidity from the initializer to this contract
        IERC20(liquidityAsset).transferFrom(msg.sender, address(this), MIN_TOTAL_SUPPLY);

        // mint a small amount of shares to a dead account so the total supply can never be zero
        // This avoids donation attacks when there are no assets in the ARM contract
        _mint(DEAD_ACCOUNT, MIN_TOTAL_SUPPLY);

        // Set the sell price to its highest value. 1.0
        traderate0 = PRICE_SCALE;
        // Set the buy price to its lowest value. 0.998
        traderate1 = PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION;
        emit TraderateChanged(traderate0, traderate1);

        // Initialize the last available assets to the current available assets
        // This ensures no performance fee is accrued when the performance fee is calculated when the fee is set
        (uint256 availableAssets,) = _availableAssets();
        lastAvailableAssets = SafeCast.toInt128(SafeCast.toInt256(availableAssets));
        _setFee(_fee);
        _setFeeCollector(_feeCollector);

        capManager = _capManager;
        emit CapManagerUpdated(_capManager);

        crossPrice = PRICE_SCALE;
        emit CrossPriceUpdated(PRICE_SCALE);
    }

    ////////////////////////////////////////////////////
    ///                 Swap Functions
    ////////////////////////////////////////////////////

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible.
     * msg.sender should have already given the ARM contract an allowance of
     * at least amountIn on the input token.
     *
     * @param inToken Input token.
     * @param outToken Output token.
     * @param amountIn The amount of input tokens to send.
     * @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
     * @param to Recipient of the output tokens.
     */
    function swapExactTokensForTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external virtual {
        uint256 amountOut = _swapExactTokensForTokens(inToken, outToken, amountIn, to);
        require(amountOut >= amountOutMin, "ARM: Insufficient output amount");
    }

    /**
     * @notice Uniswap V2 Router compatible interface. Swaps an exact amount of
     * input tokens for as many output tokens as possible.
     * msg.sender should have already given the ARM contract an allowance of
     * at least amountIn on the input token.
     *
     * @param amountIn The amount of input tokens to send.
     * @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
     * @param path The input and output token addresses.
     * @param to Recipient of the output tokens.
     * @param deadline Unix timestamp after which the transaction will revert.
     * @return amounts The input and output token amounts.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual returns (uint256[] memory amounts) {
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

    /**
     * @notice Receive an exact amount of output tokens for as few input tokens as possible.
     * msg.sender should have already given the router an allowance of
     * at least amountInMax on the input token.
     *
     * @param inToken Input token.
     * @param outToken Output token.
     * @param amountOut The amount of output tokens to receive.
     * @param amountInMax The maximum amount of input tokens that can be required before the transaction reverts.
     * @param to Recipient of the output tokens.
     */
    function swapTokensForExactTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountOut,
        uint256 amountInMax,
        address to
    ) external virtual {
        uint256 amountIn = _swapTokensForExactTokens(inToken, outToken, amountOut, to);

        require(amountIn <= amountInMax, "ARM: Excess input amount");
    }

    /**
     * @notice Uniswap V2 Router compatible interface. Receive an exact amount of
     * output tokens for as few input tokens as possible.
     * msg.sender should have already given the router an allowance of
     * at least amountInMax on the input token.
     *
     * @param amountOut The amount of output tokens to receive.
     * @param amountInMax The maximum amount of input tokens that can be required before the transaction reverts.
     * @param path The input and output token addresses.
     * @param to Recipient of the output tokens.
     * @param deadline Unix timestamp after which the transaction will revert.
     * @return amounts The input and output token amounts.
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual returns (uint256[] memory amounts) {
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

    /// @dev Ensure any liquidity assets reserved for the withdrawal queue are not used
    /// in swaps that send liquidity assets out of the ARM
    function _transferAsset(address asset, address to, uint256 amount) internal virtual {
        if (asset == liquidityAsset) _requireLiquidityAvailable(amount);

        IERC20(asset).transfer(to, amount);
    }

    /// @dev Hook to transfer assets into the ARM contract
    function _transferAssetFrom(address asset, address from, address to, uint256 amount) internal virtual {
        IERC20(asset).transferFrom(from, to, amount);
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, address to)
        internal
        virtual
        returns (uint256 amountOut)
    {
        uint256 price;
        if (inToken == token0) {
            require(outToken == token1, "ARM: Invalid out token");
            price = traderate0;
        } else if (inToken == token1) {
            require(outToken == token0, "ARM: Invalid out token");
            price = traderate1;
        } else {
            revert("ARM: Invalid in token");
        }
        amountOut = amountIn * price / PRICE_SCALE;

        // Transfer the input tokens from the caller to this ARM contract
        _transferAssetFrom(address(inToken), msg.sender, address(this), amountIn);

        // Transfer the output tokens to the recipient
        _transferAsset(address(outToken), to, amountOut);
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountOut, address to)
        internal
        virtual
        returns (uint256 amountIn)
    {
        uint256 price;
        if (inToken == token0) {
            require(outToken == token1, "ARM: Invalid out token");
            price = traderate0;
        } else if (inToken == token1) {
            require(outToken == token0, "ARM: Invalid out token");
            price = traderate1;
        } else {
            revert("ARM: Invalid in token");
        }
        // always round in our favor
        // +1 for truncation when dividing integers
        // +2 to cover stETH transfers being up to 2 wei short of the requested transfer amount
        amountIn = ((amountOut * PRICE_SCALE) / price) + 3;

        // Transfer the input tokens from the caller to this ARM contract
        _transferAssetFrom(address(inToken), msg.sender, address(this), amountIn);

        // Transfer the output tokens to the recipient
        _transferAsset(address(outToken), to, amountOut);
    }

    /**
     * @notice Set exchange rates from an operator account from the ARM's perspective.
     * If token 0 is WETH and token 1 is stETH, then both prices will be set using the stETH/WETH price.
     * @param buyT1 The price the ARM buys Token 1 (stETH) from the Trader, denominated in Token 0 (WETH), scaled to 36 decimals.
     * From the Trader's perspective, this is the sell price.
     * @param sellT1 The price the ARM sells Token 1 (stETH) to the Trader, denominated in Token 0 (WETH), scaled to 36 decimals.
     * From the Trader's perspective, this is the buy price.
     */
    function setPrices(uint256 buyT1, uint256 sellT1) external onlyOperatorOrOwner {
        // Ensure buy price is always below past sell prices
        require(sellT1 >= crossPrice, "ARM: sell price too low");
        require(buyT1 < crossPrice, "ARM: buy price too high");

        traderate0 = PRICE_SCALE * PRICE_SCALE / sellT1; // quote (t0) -> base (t1); eg WETH -> stETH
        traderate1 = buyT1; // base (t1) -> quote (t0). eg stETH -> WETH

        emit TraderateChanged(traderate0, traderate1);
    }

    /**
     * @notice set the price that buy and sell prices can not cross.
     * That is, the buy prices must be below the cross price
     * and the sell prices must be above the cross price.
     * If the cross price is being lowered, there can not be a significant amount of base assets in the ARM. eg stETH.
     * This prevents the ARM making a loss when the base asset is sold at a lower price than it was bought
     * before the cross price was lowered.
     * The base assets should be sent to the withdrawal queue before the cross price can be lowered. For example, the
     * `Owner` should construct a tx that calls `requestLidoWithdrawals` before `setCrossPrice` for the Lido ARM
     * when the cross price is being lowered.
     * The cross price can be increased with assets in the ARM.
     * @param newCrossPrice The new cross price scaled to 36 decimals.
     */
    function setCrossPrice(uint256 newCrossPrice) external onlyOwner {
        require(newCrossPrice >= PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION, "ARM: cross price too low");
        require(newCrossPrice <= PRICE_SCALE, "ARM: cross price too high");
        // The exiting sell price must be greater than or equal to the new cross price
        require(PRICE_SCALE * PRICE_SCALE / traderate0 >= newCrossPrice, "ARM: sell price too low");
        // The existing buy price must be less than the new cross price
        require(traderate1 < newCrossPrice, "ARM: buy price too high");

        // If the cross price is being lowered, there can not be a significant amount of base assets in the ARM. eg stETH.
        // This prevents the ARM making a loss when the base asset is sold at a lower price than it was bought
        // before the cross price was lowered.
        if (newCrossPrice < crossPrice) {
            // Check there is not a significant amount of base assets in the ARM
            require(IERC20(baseAsset).balanceOf(address(this)) < MIN_TOTAL_SUPPLY, "ARM: too many base assets");
        }

        // Save the new cross price to storage
        crossPrice = newCrossPrice;

        emit CrossPriceUpdated(newCrossPrice);
    }

    ////////////////////////////////////////////////////
    ///         Liquidity Provider Functions
    ////////////////////////////////////////////////////

    /// @notice Preview the amount of shares that would be minted for a given amount of assets
    /// @param assets The amount of liquidity assets to deposit
    /// @return shares The amount of shares that would be minted
    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        shares = convertToShares(assets);
    }

    /// @notice deposit liquidity assets in exchange for liquidity provider (LP) shares.
    /// The caller needs to have approved the contract to transfer the assets.
    /// @param assets The amount of liquidity assets to deposit
    /// @return shares The amount of shares that were minted
    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = _deposit(assets, msg.sender);
    }

    /// @notice deposit liquidity assets in exchange for liquidity provider (LP) shares.
    /// Funds will be transferred from msg.sender.
    /// @param assets The amount of liquidity assets to deposit
    /// @param receiver The address that will receive shares.
    /// @return shares The amount of shares that were minted
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = _deposit(assets, receiver);
    }

    /// @dev Internal logic for depositing liquidity assets in exchange for liquidity provider (LP) shares.
    function _deposit(uint256 assets, address receiver) internal returns (uint256 shares) {
        // Calculate the amount of shares to mint after the performance fees have been accrued
        // which reduces the available assets, and before new assets are deposited.
        shares = convertToShares(assets);

        // Add the deposited assets to the last available assets
        lastAvailableAssets += SafeCast.toInt128(SafeCast.toInt256(assets));

        // Transfer the liquidity asset from the sender to this contract
        IERC20(liquidityAsset).transferFrom(msg.sender, address(this), assets);

        // mint shares
        _mint(receiver, shares);

        // Check the liquidity provider caps after the new assets have been deposited
        if (capManager != address(0)) {
            ICapManager(capManager).postDepositHook(receiver, assets);
        }

        emit Deposit(receiver, assets, shares);
    }

    /// @notice Preview the amount of assets that would be received for burning a given amount of shares
    /// @param shares The amount of shares to burn
    /// @return assets The amount of liquidity assets that would be received
    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

    /// @notice Request to redeem liquidity provider shares for liquidity assets
    /// @param shares The amount of shares the redeemer wants to burn for liquidity assets
    /// @return requestId The index of the withdrawal request
    /// @return assets The amount of liquidity assets that will be claimable by the redeemer
    function requestRedeem(uint256 shares) external returns (uint256 requestId, uint256 assets) {
        // Calculate the amount of assets to transfer to the redeemer
        assets = convertToAssets(shares);

        requestId = nextWithdrawalIndex;
        // Store the next withdrawal request
        nextWithdrawalIndex = requestId + 1;

        uint128 queued = SafeCast.toUint128(withdrawsQueued + assets);
        // Store the updated queued amount which reserves liquidity assets (WETH) in the withdrawal queue
        withdrawsQueued = queued;

        uint40 claimTimestamp = uint40(block.timestamp + claimDelay);

        // Store requests
        withdrawalRequests[requestId] = WithdrawalRequest({
            withdrawer: msg.sender,
            claimed: false,
            claimTimestamp: claimTimestamp,
            assets: SafeCast.toUint128(assets),
            queued: queued
        });

        // burn redeemer's shares
        _burn(msg.sender, shares);

        // Remove the redeemed assets from the last available assets
        lastAvailableAssets -= SafeCast.toInt128(SafeCast.toInt256(assets));

        emit RedeemRequested(msg.sender, requestId, assets, queued, claimTimestamp);
    }

    /// @notice Claim liquidity assets from a previous withdrawal request after the claim delay has passed.
    /// This will withdraw from the active lending market if there are not enough liquidity assets in the ARM.
    /// @param requestId The index of the withdrawal request
    /// @return assets The amount of liquidity assets that were transferred to the redeemer
    function claimRedeem(uint256 requestId) external returns (uint256 assets) {
        // Load the struct from storage into memory
        WithdrawalRequest memory request = withdrawalRequests[requestId];

        require(request.claimTimestamp <= block.timestamp, "Claim delay not met");
        // Is there enough liquidity to claim this request?
        // This includes liquidity assets in the ARM and the the active lending market
        require(request.queued <= claimable(), "Queue pending liquidity");
        require(request.withdrawer == msg.sender, "Not requester");
        require(request.claimed == false, "Already claimed");

        assets = request.assets;

        // Store the request as claimed
        withdrawalRequests[requestId].claimed = true;
        // Store the updated claimed amount
        withdrawsClaimed += SafeCast.toUint128(assets);

        // If there is not enough liquidity assets in the ARM, get from the active market
        uint256 liquidityInARM = IERC20(liquidityAsset).balanceOf(address(this));
        if (assets > liquidityInARM) {
            uint256 liquidityFromMarket = assets - liquidityInARM;
            // This should work as we have checked earlier the claimable() amount which includes the active market
            IERC4626(activeMarket).withdraw(liquidityFromMarket, address(this), address(this));
        }

        // transfer the liquidity asset to the withdrawer
        IERC20(liquidityAsset).transfer(msg.sender, assets);

        emit RedeemClaimed(msg.sender, requestId, assets);
    }

    /// @notice Used to work out if an ARM's withdrawal request can be claimed.
    /// If the withdrawal request's `queued` amount is less than the returned `claimable` amount, then it can be claimed.
    /// The `claimable` amount is the all the withdrawals already claimed plus the liquidity assets in the ARM
    /// and active lending market.
    function claimable() public view returns (uint256 claimableAmount) {
        claimableAmount = withdrawsClaimed + IERC20(liquidityAsset).balanceOf(address(this));

        // if there is an active lending market, add to the claimable amount
        address activeMarketMem = activeMarket;
        if (activeMarketMem != address(0)) {
            claimableAmount += IERC4626(activeMarketMem).maxWithdraw(address(this));
        }
    }

    ////////////////////////////////////////////////////
    ///         Asset amount functions
    ////////////////////////////////////////////////////

    /// @dev Checks if there is enough liquidity asset (WETH) in the ARM is not reserved for the withdrawal queue.
    // That is, the amount of liquidity assets (WETH) that is available to be swapped or collected as fees.
    // If no outstanding withdrawals, no check will be done of the amount against the balance of the liquidity assets in the ARM.
    // This is a gas optimization for swaps.
    // The ARM can swap out liquidity assets (WETH) that has been accrued from the performance fee for the fee collector.
    // There is no liquidity guarantee for the fee collector. If there is not enough liquidity assets (WETH) in
    // the ARM to collect the accrued fees, then the fee collector will have to wait until there is enough liquidity assets.
    function _requireLiquidityAvailable(uint256 amount) internal view {
        // The amount of liquidity assets (WETH) that is still to be claimed in the withdrawal queue
        uint256 outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;

        // Save gas on an external balanceOf call if there are no outstanding withdrawals
        if (outstandingWithdrawals == 0) return;

        // If there is not enough liquidity assets in the ARM to cover the outstanding withdrawals and the amount
        require(
            amount + outstandingWithdrawals <= IERC20(liquidityAsset).balanceOf(address(this)),
            "ARM: Insufficient liquidity"
        );
    }

    /// @notice The total amount of assets in the ARM, active lending market and external withdrawal queue,
    /// less the liquidity assets reserved for the ARM's withdrawal queue and accrued fees.
    function totalAssets() public view virtual returns (uint256) {
        (uint256 fees, uint256 newAvailableAssets) = _feesAccrued();

        // total assets should only go up from the initial deposit amount that is burnt
        // but in case of something unforeseen, return MIN_TOTAL_SUPPLY if fees is
        // greater than or equal the available assets
        if (fees >= newAvailableAssets) return MIN_TOTAL_SUPPLY;

        // Remove the performance fee from the available assets
        return newAvailableAssets - fees;
    }

    /// @dev Calculate the available assets which is the assets in the ARM, external withdrawal queue,
    /// and active lending market, less liquidity assets reserved for the ARM's withdrawal queue.
    /// This does not exclude any accrued performance fees.
    function _availableAssets() internal view returns (uint256 availableAssets, uint256 outstandingWithdrawals) {
        // Liquidity assets, eg WETH, in the ARM and lending markets are priced at 1.0
        // Base assets, eg stETH, in the withdrawal queue are also priced at 1.0
        // Base assets, eg stETH, in the ARM are priced at the cross price which is a discounted price
        uint256 assets = IERC20(liquidityAsset).balanceOf(address(this)) + _externalWithdrawQueue()
            + IERC20(baseAsset).balanceOf(address(this)) * crossPrice / PRICE_SCALE;

        address activeMarketMem = activeMarket;
        if (activeMarketMem != address(0)) {
            // Get all the active lending market shares owned by this ARM contract
            uint256 allShares = IERC4626(activeMarketMem).balanceOf(address(this));
            // Add all the assets in the active lending market.
            // previewRedeem is used instead of maxWithdraw as maxWithdraw will return less if the market
            // is highly utilized or has a temporary pause.
            assets += IERC4626(activeMarketMem).previewRedeem(allShares);
        }

        // The amount of liquidity assets, eg WETH, that is still to be claimed in the withdrawal queue
        outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;

        // If the ARM becomes insolvent enough that the available assets in the ARM and external withdrawal queue
        // is less than the outstanding withdrawals and accrued fees.
        if (assets < outstandingWithdrawals) {
            return (0, outstandingWithdrawals);
        }

        // Need to remove the liquidity assets that have been reserved for the withdrawal queue
        availableAssets = assets - outstandingWithdrawals;
    }

    /// @dev Hook for calculating the amount of assets in an external withdrawal queue like Lido or OETH
    /// This is not the ARM's withdrawal queue
    function _externalWithdrawQueue() internal view virtual returns (uint256 assets);

    /// @notice Calculates the amount of shares for a given amount of liquidity assets
    /// @dev Total assets can't be zero. The lowest it can be is MIN_TOTAL_SUPPLY
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = assets * totalSupply() / totalAssets();
    }

    /// @notice Calculates the amount of liquidity assets for a given amount of shares
    /// @dev Total supply can't be zero. The lowest it can be is MIN_TOTAL_SUPPLY
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = (shares * totalAssets()) / totalSupply();
    }

    ////////////////////////////////////////////////////
    ///         Performance Fee Functions
    ////////////////////////////////////////////////////

    /// @notice Owner sets the performance fee on increased assets
    /// @param _fee The performance fee measured in basis points (1/100th of a percent)
    /// 10,000 = 100% performance fee
    /// 500 = 5% performance fee
    /// The max allowed performance fee is 50% (5000)
    function setFee(uint256 _fee) external onlyOwner {
        _setFee(_fee);
    }

    /// @notice Owner sets the account/contract that receives the performance fee
    function setFeeCollector(address _feeCollector) external onlyOwner {
        _setFeeCollector(_feeCollector);
    }

    function _setFee(uint256 _fee) internal {
        require(_fee <= FEE_SCALE / 2, "ARM: fee too high");

        // Collect any performance fees up to this point using the old fee
        collectFees();

        fee = SafeCast.toUint16(_fee);

        emit FeeUpdated(_fee);
    }

    function _setFeeCollector(address _feeCollector) internal {
        require(_feeCollector != address(0), "ARM: invalid fee collector");

        feeCollector = _feeCollector;

        emit FeeCollectorUpdated(_feeCollector);
    }

    /// @notice Transfer accrued performance fees to the fee collector
    /// This requires enough liquidity assets (WETH) in the ARM that are not reserved
    /// for the withdrawal queue to cover the accrued fees.
    function collectFees() public returns (uint256 fees) {
        uint256 newAvailableAssets;
        // Accrue any performance fees up to this point
        (fees, newAvailableAssets) = _feesAccrued();

        // Save the new available assets back to storage less the collected fees.
        // This needs to be done before the fees == 0 check to cover the scenario where the performance fee is zero
        // and there has been an increase in assets since the last time fees were collected.
        lastAvailableAssets = SafeCast.toInt128(SafeCast.toInt256(newAvailableAssets) - SafeCast.toInt256(fees));

        if (fees == 0) return 0;

        // Check there is enough liquidity assets (WETH) that are not reserved for the withdrawal queue
        // to cover the fee being collected.
        _requireLiquidityAvailable(fees);
        // _requireLiquidityAvailable() is optimized for swaps so will not revert if there are no outstanding withdrawals.
        // We need to check there is enough liquidity assets to cover the fees being collect from this ARM contract.
        // We could try the transfer and let it revert if there are not enough assets, but there is no error message with
        // a failed WETH transfer so we spend the extra gas to check and give a meaningful error message.
        require(fees <= IERC20(liquidityAsset).balanceOf(address(this)), "ARM: insufficient liquidity");

        IERC20(liquidityAsset).transfer(feeCollector, fees);

        emit FeeCollected(feeCollector, fees);
    }

    /// @notice Calculates the performance fees accrued since the last time fees were collected
    function feesAccrued() external view returns (uint256 fees) {
        (fees,) = _feesAccrued();
    }

    function _feesAccrued() internal view returns (uint256 fees, uint256 newAvailableAssets) {
        (newAvailableAssets,) = _availableAssets();

        // Calculate the increase in assets since the last time fees were calculated
        int256 assetIncrease = SafeCast.toInt256(newAvailableAssets) - lastAvailableAssets;

        // Do not accrued a performance fee if the available assets has decreased
        if (assetIncrease <= 0) return (0, newAvailableAssets);

        fees = SafeCast.toUint256(assetIncrease) * fee / FEE_SCALE;
    }

    ////////////////////////////////////////////////////
    ///         Lending Market Functions
    ////////////////////////////////////////////////////

    /// @notice Owner adds supported lending market to the ARM.
    /// In order to be a safe lending market for the ARM, it must be:
    ///  1. up only exchange rate
    ///  2. no slippage
    ///  3. no fees.
    /// @param _markets The addresses of the lending markets to add
    function addMarkets(address[] calldata _markets) external onlyOwner {
        for (uint256 i = 0; i < _markets.length; i++) {
            address market = _markets[i];
            require(market != address(0), "ARM: invalid market");
            require(!supportedMarkets[market], "ARM: market already supported");
            require(IERC4626(market).asset() == liquidityAsset, "ARM: invalid market asset");

            supportedMarkets[market] = true;

            emit MarketAdded(market);
        }
    }

    /// @notice Owner removes a supported lending market from the ARM.
    /// This can not be the active market.
    /// @param _market The address of the lending market to remove
    function removeMarket(address _market) external onlyOwner {
        require(_market != address(0), "ARM: invalid market");
        require(supportedMarkets[_market], "ARM: market not supported");
        require(_market != activeMarket, "ARM: market in active");

        supportedMarkets[_market] = false;

        emit MarketRemoved(_market);
    }

    /// @notice set a new active lending market for the ARM.
    /// This can be set to address(0) to disable the use of a lending market.
    function setActiveMarket(address _market) external onlyOperatorOrOwner {
        require(_market == address(0) || supportedMarkets[_market], "ARM: market not supported");
        // Read once from storage to save gas and make it clear this is the previous active market
        address previousActiveMarket = activeMarket;
        // Don't revert if the previous active market is the same as the new one
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

        // Exit if no new active market
        if (_market == address(0)) return;

        _allocate();
    }

    function allocate() external {
        require(activeMarket != address(0), "ARM: no active market");

        _allocate();
    }

    function _allocate() internal {
        (uint256 availableAssets, uint256 outstandingWithdrawals) = _availableAssets();
        if (availableAssets == 0) return;

        int256 armLiquidity = SafeCast.toInt256(IERC20(liquidityAsset).balanceOf(address(this)))
            - SafeCast.toInt256(outstandingWithdrawals);
        uint256 targetArmLiquidity = availableAssets * armBuffer / 1e18;

        int256 liquidityDelta = armLiquidity - SafeCast.toInt256(targetArmLiquidity);

        if (liquidityDelta > 0) {
            // We have too much liquidity in the ARM, we need to deposit some to the active lending market

            uint256 depositAmount = SafeCast.toUint256(liquidityDelta);

            IERC20(liquidityAsset).approve(activeMarket, depositAmount);
            IERC4626(activeMarket).deposit(depositAmount, address(this));
        } else if (liquidityDelta < 0) {
            // We have too little liquidity in the ARM, we need to withdraw some from the active lending market

            uint256 availableMarketAssets = IERC4626(activeMarket).maxWithdraw(address(this));
            uint256 desiredWithdrawAmount = SafeCast.toUint256(-liquidityDelta);

            if (availableMarketAssets < desiredWithdrawAmount) {
                // Not enough assets in the market so redeem as much as possible.
                // maxRedeem is used instead of balanceOf as we want to redeem as much as possible without failing.
                // redeem of the ARM's balance can fail if the lending market is highly utilized or temporarily paused.
                // Redeem and not withdrawal is used to avoid leaving a small amount of assets in the market.
                uint256 shares = IERC4626(activeMarket).maxRedeem(address(this));
                if (shares <= minSharesToRedeem) return;
                // This should not fail according to the ERC-4626 spec as maxRedeem was used earlier
                // but it depends on the 4626 implementation of the lending market.
                // It may fail if the market is highly utilized and not compliant with 4626.
                IERC4626(activeMarket).redeem(shares, address(this), address(this));
            } else {
                IERC4626(activeMarket).withdraw(desiredWithdrawAmount, address(this), address(this));
            }
        }

        emit Allocated(activeMarket, liquidityDelta);
    }

    ////////////////////////////////////////////////////
    ///         Admin Functions
    ////////////////////////////////////////////////////

    /// @notice Set the CapManager contract address.
    /// Set to a zero address to disable the controller.
    function setCapManager(address _capManager) external onlyOwner {
        capManager = _capManager;

        emit CapManagerUpdated(_capManager);
    }

    function setARMBuffer(uint256 _armBuffer) external onlyOwner {
        require(_armBuffer <= 1e18, "ARM: invalid arm buffer");
        armBuffer = _armBuffer;

        emit ARMBufferUpdated(_armBuffer);
    }
}
