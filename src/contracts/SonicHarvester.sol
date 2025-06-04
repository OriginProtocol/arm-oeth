// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {OwnableOperable} from "./OwnableOperable.sol";
import {IHarvestable, IMagpieRouter, IOracle} from "./Interfaces.sol";

/**
 * @title Collects rewards from strategies and swaps them for ARM liquidity tokens.
 * @author Origin Protocol Inc
 */
contract SonicHarvester is Initializable, OwnableOperable {
    using SafeERC20 for IERC20;

    enum SwapPlatform {
        Magpie
    }

    /// @notice All reward tokens are swapped to the ARM's liquidity asset.
    address public immutable liquidityAsset;

    /// @notice Mapping of strategies that rewards can be collected from
    mapping(address => bool) public supportedStrategies;
    /// @notice Oracle contract used to validate swap prices
    address public priceProvider;
    /// @notice Maximum allowed slippage denominated in basis points. Example: 300 == 3% slippage
    uint256 public allowedSlippageBps;
    /// @notice Address receiving rewards proceeds. Initially this will be the ARM contract,
    /// later this could be a Dripper contract that eases out rewards distribution.
    address public rewardRecipient;
    /// @notice The address of the Magpie router that performs swaps
    address public magpieRouter;

    uint256[45] private _gap;

    event SupportedStrategyUpdate(address strategy, bool isSupported);
    event RewardTokenSwapped(
        address indexed rewardToken,
        address indexed swappedInto,
        SwapPlatform swapPlatform,
        uint256 amountIn,
        uint256 amountOut
    );
    event RewardsCollected(address[] indexed strategy, address[][] rewardTokens, uint256[][] amounts);
    event RewardRecipientUpdated(address rewardRecipient);
    event AllowedSlippageUpdated(uint256 allowedSlippageBps);
    event PriceProviderUpdated(address priceProvider);
    event MagpieRouterUpdated(address router);

    error SlippageError(uint256 actualBalance, uint256 minExpected); // 0x2d96fff0
    error BalanceMismatchAfterSwap(uint256 actualBalance, uint256 minExpected); // 0x62baa1be
    error InvalidSwapPlatform(SwapPlatform swapPlatform); // 0x36cb1d21
    error UnsupportedStrategy(address strategyAddress); // 0x04228892
    error InvalidSwapRecipient(address recipient); // 0x1a7c14f3
    error InvalidFromAsset(address fromAsset); // 0xc3e1c198
    error InvalidFromAssetAmount(uint256 fromAssetAmount); // 0x51444e84
    error InvalidToAsset(address toAsset); // 0xdc851a18
    error EmptyLiquidityAsset(); // 0x0c82ef26
    error EmptyMagpieRouter(); // 0x24444713
    error EmptyRewardRecipient(); // 0x0c45e033
    error InvalidDecimals(); // 0xd25598a0
    error InvalidAllowedSlippage(uint256 allowedSlippageBps); // 0xfbdd3e50

    constructor(address _liquidityAsset) {
        if (_liquidityAsset == address(0)) revert EmptyLiquidityAsset();
        if (IERC20Metadata(_liquidityAsset).decimals() != 18) revert InvalidDecimals();

        liquidityAsset = _liquidityAsset;
    }

    function initialize(
        address _priceProvider,
        uint256 _allowedSlippageBps,
        address _rewardRecipient,
        address _magpieRouter
    ) external initializer onlyOwner {
        _setPriceProvider(_priceProvider);
        _setAllowedSlippage(_allowedSlippageBps);
        _setRewardRecipient(_rewardRecipient);
        _setMagpieRouter(_magpieRouter);
    }

    /**
     * @notice Collect reward tokens from each strategy into this harvester contract.
     * Can be called by anyone.
     * @param _strategies Addresses of the supported strategies to collect rewards from
     */
    function collect(address[] calldata _strategies)
        external
        returns (address[][] memory rewardTokens, uint256[][] memory amounts)
    {
        rewardTokens = new address[][](_strategies.length);
        amounts = new uint256[][](_strategies.length);

        for (uint256 i = 0; i < _strategies.length; ++i) {
            if (!supportedStrategies[_strategies[i]]) {
                revert UnsupportedStrategy(_strategies[i]);
            }
            (rewardTokens[i], amounts[i]) = IHarvestable(_strategies[i]).collectRewards();
        }

        emit RewardsCollected(_strategies, rewardTokens, amounts);
    }

    /**
     * @notice Swaps the reward token to the ARM's liquidity asset using a DEX aggregator.
     * @dev The initial implementation only supports the Magpie DEX aggregator.
     * The fromAsset, fromAssetAmount, toAsset and recipient are validated against the
     * platform specific swap data.
     * @param swapPlatform The swap platform to use. Currently only Magpie is supported.
     * @param fromAsset The address of the reward token to swap from.
     * @param fromAssetAmount The amount of reward tokens to swap from.
     * @param data aggregator specific data. eg Magpie's swapWithMagpieSignature data
     * @return toAssetAmount The amount of liquidity assets received from the swap.
     */
    function swap(SwapPlatform swapPlatform, address fromAsset, uint256 fromAssetAmount, bytes calldata data)
        external
        onlyOperatorOrOwner
        returns (uint256 toAssetAmount)
    {
        uint256 liquidityAssetsBefore = IERC20(liquidityAsset).balanceOf(address(this));

        // Validate the swap data and do the swap
        toAssetAmount = _doSwap(swapPlatform, fromAsset, fromAssetAmount, data);

        // Check this Harvester got the reported amount of liquidity assets
        uint256 liquidityAssetsReceived = IERC20(liquidityAsset).balanceOf(address(this)) - liquidityAssetsBefore;
        if (liquidityAssetsReceived < toAssetAmount) {
            revert BalanceMismatchAfterSwap(liquidityAssetsReceived, toAssetAmount);
        }

        emit RewardTokenSwapped(fromAsset, liquidityAsset, swapPlatform, fromAssetAmount, toAssetAmount);

        // If there is no price provider, we exit early
        if (priceProvider == address(0)) return toAssetAmount;

        // Get the Oracle price from the price provider
        uint256 oraclePrice = IOracle(priceProvider).price(fromAsset);

        // Calculate the minimum expected amount from the max slippage from the Oracle price
        uint256 minExpected = (fromAssetAmount * (1e4 - allowedSlippageBps) * oraclePrice) // max allowed slippage
            / 1e4 // fix the max slippage decimal position
            / 1e18; // and oracle price decimals position

        if (toAssetAmount < minExpected) {
            revert SlippageError(toAssetAmount, minExpected);
        }

        // Transfer the liquidity assets to the reward recipient
        IERC20(liquidityAsset).safeTransfer(rewardRecipient, toAssetAmount);
    }

    /// @dev Platform specific swap logic
    function _doSwap(SwapPlatform swapPlatform, address fromAsset, uint256 fromAssetAmount, bytes memory data)
        internal
        returns (uint256 toAssetAmount)
    {
        if (swapPlatform == SwapPlatform.Magpie) {
            address parsedRecipient;
            address parsedFromAsset;
            address parsedToAsset;
            uint256 fromAssetAmountShift;
            uint256 fromAssetAmountOffset;
            uint256 parsedFromAssetAmount;

            assembly {
                // Length: 32 bytes (n padded).
                // then there is 4 bytes of unknown data
                // so the data offset of 32 + 4 = 36 bytes

                // Load the swap recipient address (20 bytes) starting at offset 36
                parsedRecipient := mload(add(data, 36))
                // Shift right by 96 bits (32 - 20 bytes) to get only the 20 bytes
                parsedRecipient := shr(96, parsedRecipient)

                // Load the swap from asset address (20 bytes) starting at offset 36 + 20
                parsedFromAsset := mload(add(data, 56))
                // Shift right by 96 bits (32 - 20 bytes) to get only the 20 bytes
                parsedFromAsset := shr(96, parsedFromAsset)

                // Load the swap from asset address (20 bytes) starting at offset 36 + 20 + 20
                parsedToAsset := mload(add(data, 76))
                // Shift right by 96 bits (32 - 20 bytes) to get only the 20 bytes
                parsedToAsset := shr(96, parsedToAsset)

                // Load the fromAssetAmount
                // load the first byte which is the number of bytes to shift fromAssetAmount.
                // ie 32 bytes - fromAssetAmount length in bytes
                // For example, 1e18 is 8 bytes long so needs to be shifted 32 - 8 = 24 bytes = 196 bits
                fromAssetAmountShift := mload(add(data, 105))
                // Shift right by 248 bits (32 - 31 bytes) to get only the 1 byte
                fromAssetAmountShift := shr(248, fromAssetAmountShift)

                // load the next two bytes which is the position of fromAssetAmount in the data
                fromAssetAmountOffset := mload(add(data, 106))
                // Shift right by 240 bits (32 - 30 bytes) to get only the 2 bytes
                fromAssetAmountOffset := shr(240, fromAssetAmountOffset)
                // Subtract 36 bytes as the position are different to calldata used by Magpie
                fromAssetAmountOffset := sub(fromAssetAmountOffset, 36)

                // load the amountIn from the offset
                parsedFromAssetAmount := mload(add(data, fromAssetAmountOffset))
                parsedFromAssetAmount := shr(fromAssetAmountShift, parsedFromAssetAmount)
            }

            if (address(this) != parsedRecipient) revert InvalidSwapRecipient(parsedRecipient);
            if (fromAsset != parsedFromAsset) revert InvalidFromAsset(parsedFromAsset);
            if (liquidityAsset != parsedToAsset) revert InvalidToAsset(parsedToAsset);
            if (fromAssetAmount != parsedFromAssetAmount) revert InvalidFromAssetAmount(parsedFromAssetAmount);

            // Approve the Magpie Router to spend the fromAsset
            IERC20(fromAsset).approve(magpieRouter, fromAssetAmount);
            // Call the Magpie router to do the swap
            toAssetAmount = IMagpieRouter(magpieRouter).swapWithMagpieSignature(data);
        } else {
            revert InvalidSwapPlatform(swapPlatform);
        }
    }

    ////////////////////////////////////////////////////
    ///             Admin Functions
    ////////////////////////////////////////////////////

    /// @notice Set the address of the price provider contract providing Oracle prices.
    /// @param _priceProvider Address of the price provider contract
    function setPriceProvider(address _priceProvider) external onlyOwner {
        _setPriceProvider(_priceProvider);
    }

    /// @notice Set the maximum allowed slippage on swaps from the Oracle price.
    /// @param _allowedSlippageBps denominated in basis points. Example: 300 == 3% slippage
    function setAllowedSlippage(uint256 _allowedSlippageBps) external onlyOwner {
        _setAllowedSlippage(_allowedSlippageBps);
    }

    /// @notice Set a new reward recipient that receives liquidity assets after
    /// rewards tokens are swapped.
    /// @param _rewardRecipient Address of the new reward recipient
    function setRewardRecipient(address _rewardRecipient) external onlyOwner {
        _setRewardRecipient(_rewardRecipient);
    }

    /// @notice Flags a strategy as supported or not supported.
    /// @param _strategyAddress Address of the strategy contract.
    /// @param _isSupported Bool marking strategy as supported or not supported
    function setSupportedStrategy(address _strategyAddress, bool _isSupported) external onlyOwner {
        supportedStrategies[_strategyAddress] = _isSupported;

        emit SupportedStrategyUpdate(_strategyAddress, _isSupported);
    }

    /// @notice Set the MagpieRouter address
    /// @param _router New router address
    function setMagpieRouter(address _router) external onlyOwner {
        _setMagpieRouter(_router);
    }

    function _setPriceProvider(address _priceProvider) internal {
        priceProvider = _priceProvider;

        emit PriceProviderUpdated(_priceProvider);
    }

    function _setAllowedSlippage(uint256 _allowedSlippageBps) internal {
        if (_allowedSlippageBps > 1000) revert InvalidAllowedSlippage(_allowedSlippageBps);
        allowedSlippageBps = _allowedSlippageBps;

        emit AllowedSlippageUpdated(_allowedSlippageBps);
    }

    function _setRewardRecipient(address _rewardRecipient) internal {
        if (_rewardRecipient == address(0)) revert EmptyRewardRecipient();

        rewardRecipient = _rewardRecipient;

        emit RewardRecipientUpdated(_rewardRecipient);
    }

    function _setMagpieRouter(address _router) internal {
        if (_router == address(0)) revert EmptyMagpieRouter();

        magpieRouter = _router;

        emit MagpieRouterUpdated(_router);
    }
}
