// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {OwnableOperable} from "./OwnableOperable.sol";
import {IERC20, ILiquidityProviderController} from "./Interfaces.sol";

abstract contract AbstractARM is OwnableOperable, ERC20Upgradeable {
    ////////////////////////////////////////////////////
    ///                 Constants
    ////////////////////////////////////////////////////

    /// @notice Maximum amount the Operator can set the price from 1 scaled to 36 decimals.
    /// 1e33 is a 0.1% deviation, or 10 basis points.
    uint256 public constant MAX_PRICE_DEVIATION = 1e33;
    /// @notice Scale of the prices.
    uint256 public constant PRICE_SCALE = 1e36;
    /// @notice The delay before a withdrawal request can be claimed in seconds
    uint256 public constant CLAIM_DELAY = 10 minutes;
    /// @dev The amount of shares that are minted to a dead address on initalization
    uint256 internal constant MIN_TOTAL_SUPPLY = 1e12;
    /// @dev The address with no known private key that the initial shares are minted to
    address internal constant DEAD_ACCOUNT = 0x000000000000000000000000000000000000dEaD;
    /// @notice The scale of the performance fee
    /// 10,000 = 100% performance fee
    uint256 public constant FEE_SCALE = 10000;

    ////////////////////////////////////////////////////
    ///             Immutable Variables
    ////////////////////////////////////////////////////

    /// @notice The address of the asset that is used to add and remove liquidity. eg WETH
    address public immutable liquidityAsset;
    /// @notice The swap input token that is transferred to this contract.
    /// From a User perspective, this is the token being sold.
    /// token0 is also compatible with the Uniswap V2 Router interface.
    IERC20 public immutable token0;
    /// @notice The swap output token that is transferred from this contract.
    /// From a User perspective, this is the token being bought.
    /// token1 is also compatible with the Uniswap V2 Router interface.
    IERC20 public immutable token1;

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

    /// @notice cumulative total of all withdrawal requests included the ones that have already been claimed
    uint120 public withdrawsQueued;
    /// @notice total of all the withdrawal requests that have been claimed
    uint120 public withdrawsClaimed;
    /// @notice index of the next withdrawal request starting at 0
    uint16 public nextWithdrawalIndex;

    struct WithdrawalRequest {
        address withdrawer;
        bool claimed;
        // When the withdrawal can be claimed
        uint40 claimTimestamp;
        // Amount of assets to withdraw
        uint120 assets;
        // cumulative total of all withdrawal requests including this one.
        // this request can be claimed when this queued amount is less than or equal to the queue's claimable amount.
        uint120 queued;
    }

    /// @notice Mapping of withdrawal request indices to the user withdrawal request data
    mapping(uint256 requestId => WithdrawalRequest) public withdrawalRequests;

    /// @notice Performance fee that is collected by the feeCollector measured in basis points (1/100th of a percent)
    /// 10,000 = 100% performance fee
    /// 2,000 = 20% performance fee
    /// 500 = 5% performance fee
    uint16 public fee;
    /// @notice The available assets the the last time performance fees were collected and adjusted
    /// for liquidity assets (WETH) deposited and redeemed.
    /// This can be negative if there were asset gains and then all the liquidity providers redeemed.
    int128 public lastAvailableAssets;
    /// @notice The account that can collect the performance fee
    address public feeCollector;

    address public liquidityProviderController;

    uint256[42] private _gap;

    ////////////////////////////////////////////////////
    ///                 Events
    ////////////////////////////////////////////////////

    event TraderateChanged(uint256 traderate0, uint256 traderate1);
    event Deposit(address indexed owner, uint256 assets, uint256 shares);
    event RedeemRequested(
        address indexed withdrawer, uint256 indexed requestId, uint256 assets, uint256 queued, uint256 claimTimestamp
    );
    event RedeemClaimed(address indexed withdrawer, uint256 indexed requestId, uint256 assets);
    event FeeCollected(address indexed feeCollector, uint256 fee);
    event FeeUpdated(uint256 fee);
    event FeeCollectorUpdated(address indexed newFeeCollector);
    event LiquidityProviderControllerUpdated(address indexed liquidityProviderController);

    constructor(address _token0, address _token1, address _liquidityAsset) {
        require(IERC20(_token0).decimals() == 18);
        require(IERC20(_token1).decimals() == 18);

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        _setOwner(address(0)); // Revoke owner for implementation contract at deployment

        require(_liquidityAsset == address(token0) || _liquidityAsset == address(token1), "invalid liquidity asset");
        liquidityAsset = _liquidityAsset;
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
    /// @param _liquidityProviderController The address of the Liquidity Provider Controller
    function _initARM(
        address _operator,
        string calldata _name,
        string calldata _symbol,
        uint256 _fee,
        address _feeCollector,
        address _liquidityProviderController
    ) internal {
        _initOwnableOperable(_operator);

        __ERC20_init(_name, _symbol);

        // Transfer a small bit of liquidity from the intializer to this contract
        IERC20(liquidityAsset).transferFrom(msg.sender, address(this), MIN_TOTAL_SUPPLY);

        // mint a small amount of shares to a dead account so the total supply can never be zero
        // This avoids donation attacks when there are no assets in the ARM contract
        _mint(DEAD_ACCOUNT, MIN_TOTAL_SUPPLY);

        // Initialize the last available assets to the current available assets
        // This ensures no performance fee is accrued when the performance fee is calculated when the fee is set
        lastAvailableAssets = SafeCast.toInt128(SafeCast.toInt256(_availableAssets()));
        _setFee(_fee);
        _setFeeCollector(_feeCollector);

        liquidityProviderController = _liquidityProviderController;
        emit LiquidityProviderControllerUpdated(_liquidityProviderController);
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
        if (asset == liquidityAsset) {
            require(amount <= _liquidityAvailable(), "ARM: Insufficient liquidity");
        }

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
        amountIn = ((amountOut * PRICE_SCALE) / price) + 1; // +1 to always round in our favor

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
        // Limit funds and loss when called by the Operator
        if (msg.sender == operator) {
            require(sellT1 >= PRICE_SCALE - MAX_PRICE_DEVIATION, "ARM: sell price too low");
            require(buyT1 <= PRICE_SCALE + MAX_PRICE_DEVIATION, "ARM: buy price too high");
        }
        _setTraderates(
            PRICE_SCALE * PRICE_SCALE / sellT1, // base (t0) -> token (t1)
            buyT1 // token (t1) -> base (t0)
        );
    }

    function _setTraderates(uint256 _baseToTokenRate, uint256 _tokenToBaseRate) internal {
        require((PRICE_SCALE * PRICE_SCALE / (_baseToTokenRate)) > _tokenToBaseRate, "ARM: Price cross");
        traderate0 = _baseToTokenRate;
        traderate1 = _tokenToBaseRate;

        emit TraderateChanged(_baseToTokenRate, _tokenToBaseRate);
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
        // Calculate the amount of shares to mint after the performance fees have been accrued
        // which reduces the available assets, and before new assets are deposited.
        shares = convertToShares(assets);

        // Transfer the liquidity asset from the sender to this contract
        IERC20(liquidityAsset).transferFrom(msg.sender, address(this), assets);

        // mint shares
        _mint(msg.sender, shares);

        // Add the deposited assets to the last available assets
        lastAvailableAssets += SafeCast.toInt128(SafeCast.toInt256(assets));

        // Check the liquidity provider caps after the new assets have been deposited
        if (liquidityProviderController != address(0)) {
            ILiquidityProviderController(liquidityProviderController).postDepositHook(msg.sender, assets);
        }

        emit Deposit(msg.sender, assets, shares);
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
        uint120 queued = SafeCast.toUint120(withdrawsQueued + assets);
        uint40 claimTimestamp = uint40(block.timestamp + CLAIM_DELAY);

        // Store the next withdrawal request
        nextWithdrawalIndex = SafeCast.toUint16(requestId + 1);
        // Store the updated queued amount which reserves WETH in the withdrawal queue
        withdrawsQueued = queued;
        // Store requests
        withdrawalRequests[requestId] = WithdrawalRequest({
            withdrawer: msg.sender,
            claimed: false,
            claimTimestamp: claimTimestamp,
            assets: SafeCast.toUint120(assets),
            queued: queued
        });

        // burn redeemer's shares
        _burn(msg.sender, shares);

        // Remove the redeemed assets from the last available assets
        lastAvailableAssets -= SafeCast.toInt128(SafeCast.toInt256(assets));

        emit RedeemRequested(msg.sender, requestId, assets, queued, claimTimestamp);
    }

    /// @notice Claim liquidity assets from a previous withdrawal request after the claim delay has passed
    /// @param requestId The index of the withdrawal request
    /// @return assets The amount of liquidity assets that were transferred to the redeemer
    function claimRedeem(uint256 requestId) external returns (uint256 assets) {
        // Load the structs from storage into memory
        WithdrawalRequest memory request = withdrawalRequests[requestId];

        require(request.claimTimestamp <= block.timestamp, "Claim delay not met");
        // Is there enough liquidity to claim this request?
        require(
            request.queued <= withdrawsClaimed + IERC20(liquidityAsset).balanceOf(address(this)),
            "Queue pending liquidity"
        );
        require(request.withdrawer == msg.sender, "Not requester");
        require(request.claimed == false, "Already claimed");

        // Store the request as claimed
        withdrawalRequests[requestId].claimed = true;
        // Store the updated claimed amount
        withdrawsClaimed += request.assets;

        assets = request.assets;

        emit RedeemClaimed(msg.sender, requestId, assets);

        // transfer the liquidity asset to the withdrawer
        IERC20(liquidityAsset).transfer(msg.sender, assets);
    }

    /// @notice Check if a withdrawal request can be claimed
    /// @param requestId The index of the withdrawal request
    function isClaimable(uint256 requestId) public view returns (bool) {
        return
            withdrawalRequests[requestId].queued <= withdrawsClaimed + IERC20(liquidityAsset).balanceOf(address(this));
    }

    /// @dev Calculate how much of the liquidity asset (WETH) in the ARM is not reserved for the withdrawal queue.
    // That is, the amount of liquidity assets (WETH) that is available to be swapped.
    // If there are no outstanding withdrawals, then return the maximum uint256 value.
    // The ARM can swap out liquidity assets (WETH) that has been accrued from the performance fee for the fee collector.
    // There is no liquidity guarantee for the fee collector. If there is not enough liquidity assets (WETH) in
    // the ARM to collect the accrued fees, then the fee collector will have to wait until there is enough liquidity assets.
    function _liquidityAvailable() internal view returns (uint256) {
        // The amount of WETH that is still to be claimed in the withdrawal queue
        uint256 outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;

        // Save gas on an external balanceOf call if there are no outstanding withdrawals
        if (outstandingWithdrawals == 0) return type(uint256).max;

        // The amount of the liquidity asset is in the ARM
        uint256 liquidityBalance = IERC20(liquidityAsset).balanceOf(address(this));

        // If there is not enough liquidity assets in the ARM to cover the outstanding withdrawals
        if (liquidityBalance <= outstandingWithdrawals) {
            return 0;
        }

        return liquidityBalance - outstandingWithdrawals;
    }

    /// @notice The total amount of assets in the ARM and external withdrawal queue,
    /// less the liquidity assets reserved for the ARM's withdrawal queue and accrued fees.
    function totalAssets() public view virtual returns (uint256) {
        (uint256 fees, uint256 newAvailableAssets) = _feesAccrued();

        if (fees > newAvailableAssets) return 0;

        // Calculate the performance fee and remove from the available assets
        return newAvailableAssets - fees;
    }

    /// @dev Calculate the available assets which is the assets in the ARM, external withdrawal queue,
    /// less liquidity assets reserved for the ARM's withdrawal queue.
    /// This does not exclude any accrued performance fees.
    function _availableAssets() internal view returns (uint256) {
        // Get the assets in the ARM and external withdrawal queue
        uint256 assets = token0.balanceOf(address(this)) + token1.balanceOf(address(this)) + _externalWithdrawQueue();

        // Load the queue metadata from storage into memory
        uint256 queuedMem = withdrawsQueued;
        uint256 claimedMem = withdrawsClaimed;

        // If the ARM becomes insolvent enough that the available assets in the ARM and external withdrawal queue
        // is less than the outstanding withdrawals and accrued fees.
        if (assets + claimedMem < queuedMem) {
            return 0;
        }

        // Need to remove the liquidity assets that have been reserved for the withdrawal queue
        return assets + claimedMem - queuedMem;
    }

    /// @dev Hook for calculating the amount of assets in an external withdrawal queue like Lido or OETH
    /// This is not the ARM's withdrawal queue
    function _externalWithdrawQueue() internal view virtual returns (uint256 assets);

    /// @notice Calculates the amount of shares for a given amount of liquidity assets
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        uint256 totalAssetsMem = totalAssets();
        shares = (totalAssetsMem == 0) ? assets : (assets * totalSupply()) / totalAssetsMem;
    }

    /// @notice Calculates the amount of liquidity assets for a given amount of shares
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = (shares * totalAssets()) / totalSupply();
    }

    /// @notice Set the Liquidity Provider Controller contract address.
    /// Set to a zero address to disable the controller.
    function setLiquidityProviderController(address _liquidityProviderController) external onlyOwner {
        liquidityProviderController = _liquidityProviderController;

        emit LiquidityProviderControllerUpdated(_liquidityProviderController);
    }

    ////////////////////////////////////////////////////
    ///         Performance Fee Functions
    ////////////////////////////////////////////////////

    /// @notice Owner sets the performance fee on increased assets
    /// @param _fee The performance fee measured in basis points (1/100th of a percent)
    /// 10,000 = 100% performance fee
    /// 500 = 5% performance fee
    function setFee(uint256 _fee) external onlyOwner {
        _setFee(_fee);
    }

    /// @notice Owner sets the account/contract that receives the performance fee
    function setFeeCollector(address _feeCollector) external onlyOwner {
        _setFeeCollector(_feeCollector);
    }

    function _setFee(uint256 _fee) internal {
        require(_fee <= FEE_SCALE, "ARM: fee too high");

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
    /// This requires enough liquidity assets in the ARM to cover the accrued fees.
    function collectFees() public returns (uint256 fees) {
        uint256 newAvailableAssets;
        // Accrue any performance fees up to this point
        (fees, newAvailableAssets) = _feesAccrued();

        if (fee == 0) return fees;

        require(fees <= IERC20(liquidityAsset).balanceOf(address(this)), "ARM: insufficient liquidity");

        IERC20(liquidityAsset).transfer(feeCollector, fees);

        // Save the new available assets back to storage less the collected fees.
        lastAvailableAssets = SafeCast.toInt128(SafeCast.toInt256(newAvailableAssets) - SafeCast.toInt256(fees));

        emit FeeCollected(feeCollector, fees);
    }

    /// @notice Calculates the performance fees accrued since the last time fees were collected
    function feesAccrued() public view returns (uint256 fees) {
        (fees,) = _feesAccrued();
    }

    function _feesAccrued() public view returns (uint256 fees, uint256 newAvailableAssets) {
        newAvailableAssets = _availableAssets();

        // Calculate the increase in assets since the last time fees were calculated
        int256 assetIncrease = SafeCast.toInt256(newAvailableAssets) - lastAvailableAssets;

        // Do not accrued a performance fee if the available assets has decreased
        if (assetIncrease <= 0) return (0, newAvailableAssets);

        fees = SafeCast.toUint256(assetIncrease) * fee / FEE_SCALE;
    }
}
