// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import {OwnableOperable} from "./OwnableOperable.sol";
import {IHarvestable, IMagpieRouter, IOracle} from "./Interfaces.sol";

abstract contract Harvester is OwnableOperable {
    using SafeERC20 for IERC20;

    enum SwapPlatform {
        Magpie
    }

    /**
     * @notice All tokens are swapped to this token before it gets transferred to the `rewardRecipient`.
     * eg WETH on Ethereum and wS on Sonic.
     */
    address public immutable baseToken;
    address public immutable magpieRouter;

    mapping(address => bool) public supportedStrategies;
    /// @notice Maximum allowed slippage denominated in basis points. Example: 300 == 3% slippage
    uint256 public allowedSlippageBps;

    /**
     * @notice Address receiving rewards proceeds. Initially the Vault contract later will possibly
     * be replaced by another contract that eases out rewards distribution.
     *
     */
    address public rewardRecipient;

    address public priceProvider;

    constructor(address _baseToken, address _magpieRouter) {
        require(_baseToken != address(0));
        require(_magpieRouter != address(0));

        require(IERC20Metadata(_baseToken).decimals() == 18, "not 18 decimals");

        baseToken = _baseToken;
        magpieRouter = _magpieRouter;
    }

    event SupportedStrategyUpdate(address strategy, bool isSupported);
    event RewardTokenSwapped(
        address indexed rewardToken,
        address indexed swappedInto,
        SwapPlatform swapPlatform,
        uint256 amountIn,
        uint256 amountOut
    );
    event rewardRecipientTransferred(address indexed token, uint256 protocolYield);
    event rewardRecipientChanged(address newProceedsAddress);

    error SlippageError(uint256 actualBalance, uint256 minExpected);
    error BalanceMismatchAfterSwap(uint256 actualBalance, uint256 minExpected);

    error EmptyAddress();
    error InvalidSlippageBps();
    error InvalidHarvestRewardBps();

    error InvalidSwapPlatform(SwapPlatform swapPlatform);

    error UnsupportedStrategy(address strategyAddress);

    /**
     * @dev Flags a strategy as supported or not supported one
     * @param _strategyAddress Address of the strategy
     * @param _isSupported Bool marking strategy as supported or not supported
     */
    function setSupportedStrategy(address _strategyAddress, bool _isSupported) external onlyOwner {
        supportedStrategies[_strategyAddress] = _isSupported;

        emit SupportedStrategyUpdate(_strategyAddress, _isSupported);
    }

    /**
     * @notice Collect reward tokens from each strategy into this harvester contract.
     * Can be called by anyone.
     * @param _strategies Addresses of the strategies to collect rewards from
     */
    function harvest(address[] calldata _strategies)
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

        // TODO emit harvest event
    }

    /**
     * @notice Swaps the reward token to the base token. The base token is then transferred to the `rewardRecipient`.
     * @param swapPlatform The swap platform to use. Currently only Magpie is supported.
     * @param fromAsset The token address of the asset being sold.
     * @param data aggregator specific data. eg Magpie swapWithMagpieSignature data
     */
    function swap(SwapPlatform swapPlatform, address fromAsset, bytes calldata data)
        external
        onlyOperatorOrOwner
        returns (uint256 toAssetAmount)
    {
        uint256 balance = IERC20(fromAsset).balanceOf(address(this));

        if (balance == 0) return 0;

        // No need to swap if the reward token is the base token. eg USDT or WETH.
        // There is also no limit on the transfer. Everything in the harvester will be transferred
        // to the Dripper regardless of the liquidationLimit config.
        if (fromAsset == baseToken) {
            IERC20(fromAsset).safeTransfer(rewardRecipient, balance);
            // currently not paying the farmer any rewards as there is no swap
            emit rewardRecipientTransferred(baseToken, balance);
            return balance;
        }

        // This'll revert if there is no price feed
        uint256 oraclePrice = IOracle(priceProvider).price(fromAsset);

        // Calculate the minimum expected amount from the max slippage from the Oracle price
        uint256 minExpected = (balance * (1e4 - allowedSlippageBps) * oraclePrice) // max allowed slippage
            / 1e4 // fix the max slippage decimal position
            / 1e18; // and oracle price decimals position

        // Do the swap
        uint256 amountReceived = _doSwap(swapPlatform, fromAsset, baseToken, data);

        if (amountReceived < minExpected) {
            revert SlippageError(amountReceived, minExpected);
        }

        emit RewardTokenSwapped(fromAsset, baseToken, swapPlatform, balance, amountReceived);

        uint256 baseTokenBalance = IERC20(baseToken).balanceOf(address(this));
        if (baseTokenBalance < amountReceived) {
            // Note: It's possible to bypass this check by transferring `baseToken`
            // directly to Harvester before calling the `harvestAndSwap`. However,
            // there's no incentive for an attacker to do that. Doing a balance diff
            // will increase the gas cost significantly
            revert BalanceMismatchAfterSwap(baseTokenBalance, amountReceived);
        }

        IERC20(baseToken).safeTransfer(rewardRecipient, amountReceived);

        emit rewardRecipientTransferred(rewardRecipient, amountReceived);
    }

    function _doSwap(SwapPlatform swapPlatform, address fromAsset, bytes memory data)
        internal
        returns (uint256 toAssetAmount)
    {
        if (swapPlatform == SwapPlatform.Magpie) {
            address parsedRecipient;
            address parsedFromAsset;
            address parsedToAsset;

            assembly {
                // Offset: 32 bytes (0x20 padded).
                // Length: 32 bytes (n padded).
                // then there is 4 bytes of unknown data
                // so the data offset of 32 + 32 + 4 = 68 bytes

                // Load the swap recipient address (20 bytes) starting at offset 68
                parsedRecipient := mload(add(data, 68))
                // Shift right by 96 bits (32 - 20 bytes) to get only the 20 bytes
                parsedRecipient := shr(96, parsedRecipient)

                // Load the swap from asset address (20 bytes) starting at offset 68 + 20
                parsedFromAsset := mload(add(data, 88))
                // Shift right by 96 bits (32 - 20 bytes) to get only the 20 bytes
                parsedFromAsset := shr(96, parsedFromAsset)

                // Load the swap from asset address (20 bytes) starting at offset 68 + 20 + 20
                parsedToAsset := mload(add(data, 108))
                // Shift right by 96 bits (32 - 20 bytes) to get only the 20 bytes
                parsedToAsset := shr(96, parsedToAsset)
            }
            require(rewardRecipient == parsedRecipient, "Invalid swap recipient");
            require(fromAsset == parsedFromAsset, "Invalid from asset");
            require(baseToken == parsedToAsset, "Invalid to asset");

            // Call the Magpie router to do the swap
            toAssetAmount = IMagpieRouter(magpieRouter).swapWithMagpieSignature(data);
        } else {
            revert InvalidSwapPlatform(swapPlatform);
        }
    }
}
