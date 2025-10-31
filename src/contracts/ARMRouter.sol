// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IWETH} from "src/contracts/Interfaces.sol";
import {IERC20} from "src/contracts/Interfaces.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

interface Wrapper {
    function wrap(uint256 amount) external returns (uint256);
    function unwrap(uint256 amount) external returns (uint256);
}

contract ARMRouter {
    ////////////////////////////////////////////////////
    ///                 Structs and Enums
    ////////////////////////////////////////////////////
    struct Config {
        bytes4 sig; // Used for wrap or unwrap differentiation
        address addr;
    }
    ////////////////////////////////////////////////////
    ///                 Constants and Immutables
    ////////////////////////////////////////////////////
    /// @notice Address of the WETH token contract.
    IWETH public immutable WETH;
    /// @notice Price scale used for traderate calculations.
    uint256 public constant PRICE_SCALE = 1e36;

    ////////////////////////////////////////////////////
    ///                 State Variables
    ////////////////////////////////////////////////////
    /// @notice Mapping to store ARM addresses for token pairs.
    mapping(address => mapping(address => Config)) internal configs;

    ////////////////////////////////////////////////////
    ///                 Constructor
    ////////////////////////////////////////////////////
    constructor(address _weth) {
        WETH = IWETH(_weth);
    }

    ////////////////////////////////////////////////////
    ///                 Modifiers
    ////////////////////////////////////////////////////
    /// @notice Ensures that the transaction is executed before the specified deadline.
    /// @param deadline The timestamp by which the transaction must be completed.
    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    ////////////////////////////////////////////////////
    ///                 Swap Functions
    ////////////////////////////////////////////////////
    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible, along the route determined by the path.
    /// @dev This is a simplified version that handles swaps in a loop without fetching amounts beforehand.
    /// @param amountIn The exact amount of input tokens to swap.
    /// @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
    /// @param path An array of token addresses representing the swap path.
    /// @param to The address that will receive the output tokens.
    /// @param deadline The timestamp by which the transaction must be completed.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        // Transfer the input tokens from the sender to this contract
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        // Perform the swaps along the path
        uint256 len = path.length;
        for (uint256 i; i < len - 1; i++) {
            address[] memory intermediate = new address[](2);
            intermediate[0] = path[i];
            intermediate[1] = path[i + 1];

            Config memory config = getConfigFor(intermediate);
            if (config.sig == bytes4(0)) {
                uint256[] memory obtained = AbstractARM(config.addr)
                    .swapExactTokensForTokens(amounts[i], 0, intermediate, i < len - 2 ? address(this) : to, deadline);
                amounts[i + 1] = obtained[1];
            } else {
                (bool success, bytes memory data) = config.addr.call(abi.encodeWithSelector(config.sig, amounts[i]));
                require(success, "ARMRouter: SWAP_FAILED");
                amounts[i + 1] = abi.decode(data, (uint256));

                // If this is the last swap, transfer to the recipient
                if (i == len - 2) IERC20(path[i + 1]).transfer(to, amounts[i + 1]);
            }
        }
        require(amounts[amounts.length - 1] >= amountOutMin, "ARMRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    /// @notice Swaps an exact amount of ETH for as many output tokens as possible, along the route determined by the path.
    /// @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
    /// @param path An array of token addresses representing the swap path.
    /// @param to The address that will receive the output tokens.
    /// @param deadline The timestamp by which the transaction must be completed.
    /// @return amounts An array of token amounts for each step in the swap path.
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == address(WETH), "ARMRouter: INVALID_PATH");

        amounts = new uint256[](path.length);
        amounts[0] = msg.value;

        // Wrap ETH to WETH
        WETH.deposit{value: amounts[0]}();

        // Perform the swaps along the path
        uint256 len = path.length;
        for (uint256 i; i < len - 1; i++) {
            address[] memory intermediate = new address[](2);
            intermediate[0] = path[i];
            intermediate[1] = path[i + 1];

            Config memory config = getConfigFor(intermediate);
            if (config.sig == bytes4(0)) {
                uint256[] memory obtained = AbstractARM(config.addr)
                    .swapExactTokensForTokens(amounts[i], 0, intermediate, i < len - 2 ? address(this) : to, deadline);
                amounts[i + 1] = obtained[1];
            } else {
                (bool success, bytes memory data) = config.addr.call(abi.encodeWithSelector(config.sig, amounts[i]));
                require(success, "ARMRouter: SWAP_FAILED");
                amounts[i + 1] = abi.decode(data, (uint256));

                // If this is the last swap, transfer to the recipient
                if (i == len - 2) IERC20(path[i + 1]).transfer(to, amounts[i + 1]);
            }
        }
        require(amounts[amounts.length - 1] >= amountOutMin, "ARMRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    ////////////////////////////////////////////////////
    ///                 Helpers Functions
    ////////////////////////////////////////////////////
    /// @notice Given a pair of tokens, returns the address of the associated ARM.
    /// @param tokenPair An array containing the addresses of the two tokens.
    /// @return arm The address of the associated ARM.
    function getConfigFor(address[] memory tokenPair) internal view returns (Config memory arm) {
        arm = configs[tokenPair[0]][tokenPair[1]];
        require(arm.addr != address(0), "ARMRouter: ARM_NOT_FOUND");
    }

    ////////////////////////////////////////////////////
    ///                 Owner Functions
    ////////////////////////////////////////////////////
    function registerConfig(address tokenA, address tokenB, bytes4 sig, address armAddress) external {
        // Max approval for router to interact with ARMs
        IERC20(tokenA).approve(armAddress, type(uint256).max);
        IERC20(tokenB).approve(armAddress, type(uint256).max);

        configs[tokenA][tokenB] = Config({sig: sig, addr: armAddress});
    }
}
