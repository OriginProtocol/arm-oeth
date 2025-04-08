// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {OwnableOperable} from "./OwnableOperable.sol";
import {IVault, IERC20} from "./Interfaces.sol";

/**
 * @title Generic Automated Redemption Manager (ARM) Strategy
 * @author Origin Protocol Inc
 */
abstract contract AbstractARMStrategy is OwnableOperable {
    ////////////////////////////////////////////////////
    ///                 Constants
    ////////////////////////////////////////////////////

    /// @notice Maximum amount the Owner can set the price below 1 scaled to 36 decimals.
    /// 20e32 is a 0.2% deviation, or 20 basis points.
    uint256 public constant MAX_PRICE_DEVIATION = 20e32;
    /// @notice Scale of the prices.
    uint256 public constant PRICE_SCALE = 1e36;

    ////////////////////////////////////////////////////
    ///             Immutable Variables
    ////////////////////////////////////////////////////

    /// @notice The address of the asset that is used to add and remove liquidity. eg WETH
    /// This is also the quote asset when the prices are set.
    /// eg the stETH/WETH price has a base asset of stETH and quote asset of WETH.
    address public immutable liquidityAsset;
    /// @notice The asset being purchased by the ARM and put in the withdrawal queue. eg stETH
    address public immutable baseAsset;
    /// @notice The address of the ARM Vault that holds the liquid assets.
    address public immutable vault;

    ////////////////////////////////////////////////////
    ///             Storage Variables
    ////////////////////////////////////////////////////

    /**
     * @notice For one `token1` from a Trader, how many `token0` does the pool send.
     * For example, if `token0` is WETH and `token1` is stETH then
     * `price` is the stETH/WETH price.
     * From a Trader's perspective, this is the sell price.
     * From a ARM's perspective, this is the buy price.
     * Rate is to 36 decimals (1e36).
     */
    uint256 public price;

    uint256[46] private _gap;

    ////////////////////////////////////////////////////
    ///                 Events
    ////////////////////////////////////////////////////

    event PriceChanged(uint256 buyPrice);

    constructor(address _baseAsset, address _liquidityAsset, address _vault) {
        require(IERC20(_baseAsset).decimals() == 18);
        require(IERC20(_liquidityAsset).decimals() == 18);

        _setOwner(address(0)); // Revoke owner for implementation contract at deployment

        baseAsset = _baseAsset;
        liquidityAsset = _liquidityAsset;
        vault = _vault;
    }

    /// @notice Initialize the contract.
    /// The deployer that calls initialize has to approve the this ARM's proxy contract to transfer 1e12 WETH.
    /// @param _operator The address of the account that can request and claim Lido withdrawals.
    function _initARM(address _operator) internal {
        _initOwnableOperable(_operator);

        // Set the buy price to its lowest value. 0.998
        price = PRICE_SCALE - MAX_PRICE_DEVIATION;
        emit PriceChanged(price);
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
        uint256 amountOut = _swapExactTokensForTokens(address(inToken), address(outToken), amountIn, to);
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

        address inToken = path[0];
        address outToken = path[1];

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
        uint256 amountIn = _swapTokensForExactTokens(address(inToken), address(outToken), amountOut, to);

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

        address inToken = path[0];
        address outToken = path[1];

        uint256 amountIn = _swapTokensForExactTokens(inToken, outToken, amountOut, to);

        require(amountIn <= amountInMax, "ARM: Excess input amount");

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    function _inDeadline(uint256 deadline) internal view {
        require(deadline >= block.timestamp, "ARM: Deadline expired");
    }

    function _swapExactTokensForTokens(address inToken, address outToken, uint256 amountIn, address to)
        internal
        virtual
        returns (uint256 amountOut)
    {
        require(inToken == baseAsset, "ARM: Invalid in token");
        require(outToken == liquidityAsset, "ARM: Invalid in token");

        amountOut = amountIn * price / PRICE_SCALE;

        // Check there is enough liquid assets in the vault to cover the swap
        require(IVault(vault).availableLiquidity() >= amountOut, "ARM: Insufficient liquidity");

        // Transfer the input tokens from the caller to this ARM contract
        IERC20(inToken).transferFrom(msg.sender, address(this), amountIn);

        // Transfer the output tokens to the recipient
        IERC20(outToken).transferFrom(vault, to, amountOut);
    }

    function _swapTokensForExactTokens(address inToken, address outToken, uint256 amountOut, address to)
        internal
        virtual
        returns (uint256 amountIn)
    {
        require(inToken == baseAsset, "ARM: Invalid in token");
        require(outToken == liquidityAsset, "ARM: Invalid in token");

        // Check there is enough liquid assets in the vault to cover the swap
        require(IVault(vault).availableLiquidity() >= amountOut, "ARM: Insufficient liquidity");

        // always round in our favor
        // +1 for truncation when dividing integers
        // +2 to cover stETH transfers being up to 2 wei short of the requested transfer amount
        amountIn = ((amountOut * PRICE_SCALE) / price) + 3;

        // Transfer the input tokens from the caller to this the ARM strategy contract
        IERC20(inToken).transferFrom(msg.sender, address(this), amountIn);

        // Transfer the output tokens to the recipient
        IERC20(outToken).transferFrom(vault, to, amountOut);
    }

    ////////////////////////////////////////////////////
    ///                 Balance Functions
    ////////////////////////////////////////////////////

    /// @notice The total amount of base assets in the ARM strategy and external withdrawal queue.
    /// This does not include any liquid assets in the ARM strategy contract.
    function checkBalance() external view virtual returns (uint256) {
        return IERC20(baseAsset).balanceOf(address(this)) + _externalWithdrawQueue();
    }

    /// @dev Hook for calculating the amount of assets in an external withdrawal queue like Lido or OETH.
    /// This is not the ARM Vault's withdrawal queue
    function _externalWithdrawQueue() internal view virtual returns (uint256 assets);

    ////////////////////////////////////////////////////
    ///                 Admin Functions
    ////////////////////////////////////////////////////

    /**
     * @notice Set exchange rates from an operator account from the ARM's perspective.
     * If the base asset is stETH and liquidity asset is WETH, then the price will be set using the stETH/WETH price.
     * @param _price The price the ARM buys Token 1 (stETH) from the Trader, denominated in Token 0 (WETH), scaled to 36 decimals.
     * From the Trader's perspective, this is the sell price.
     */
    function setPrice(uint256 _price) external virtual onlyOperatorOrOwner {
        require(_price >= PRICE_SCALE - MAX_PRICE_DEVIATION, "ARM: Price too low");
        require(_price < PRICE_SCALE, "ARM: Price too high");
        price = _price; // base (t1) -> quote (t0). eg stETH -> WETH

        emit PriceChanged(_price);
    }

    /// @notice Transfer out any ERC20 tokens that aren't meant to be in the ARM strategy contract.
    /// This includes the liquidity asset which should be held in the ARM Vault.
    /// @param _asset ERC20 token address
    function transferAllToken(address _asset) external onlyOwner {
        require(_asset != baseAsset, "ARM: Cannot transfer base asset");
        IERC20(_asset).transfer(_owner(), IERC20(_asset).balanceOf(address(this)));
    }
}
