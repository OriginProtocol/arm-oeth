// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Vm} from "dependencies/forge-std-1.9.7/src/Vm.sol";
// Contract Imports
import {Ownable} from "contracts/Ownable.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

// Library Imports
import {DynamicArrayLib} from "@solady/utils/DynamicArrayLib.sol";

// Interface Imports
import {IWETH} from "src/contracts/Interfaces.sol";
import {IERC20} from "src/contracts/Interfaces.sol";

/// @author Origin Protocol
/// @notice ARM Router contract for facilitating token swaps via ARMs and Wrappers.
contract ARMRouter is Ownable {
    using DynamicArrayLib for address[];
    using DynamicArrayLib for uint256[];

    ////////////////////////////////////////////////////
    ///                 Structs and Enums
    ////////////////////////////////////////////////////
    enum SwapType {
        ARM,
        WRAPPER
    }

    struct Config {
        /// @notice Type of swap (ARM or Wrap).
        SwapType swapType;
        /// @notice Address of the ARM or Wrapper contract.
        address addr;
        /// @notice Function signature for wrap/unwrap.
        bytes4 wrapSig;
        /// @notice Function signature for price query on wrapper.
        bytes4 priceSig;
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

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

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
        require(deadline >= block.timestamp, "ARMRouter: EXPIRED");
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

        // Perform the swaps along the path
        amounts = _swapExactTokenFor(amountIn, path, to);

        // Ensure the output amount meets the minimum requirement
        uint256 lastIndex;
        assembly {
            // lastIndex = amounts.length - 1
            lastIndex := sub(mload(amounts), 1)
        }
        require(amounts.get(lastIndex) >= amountOutMin, "ARMRouter: INSUFFICIENT_OUTPUT");
    }

    /// @notice Swaps as few input tokens as possible to receive an exact amount of output tokens, along the route determined by the path.
    /// @param amountOut The exact amount of output tokens to receive.
    /// @param amountInMax The maximum amount of input tokens that can be used for the swap.
    /// @param path An array of token addresses representing the swap path.
    /// @param to The address that will receive the output tokens.
    /// @param deadline The timestamp by which the transaction must be completed.
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] memory path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        assembly {
            // ---
            // The following assembly block is equivalent to:
            // require(path.length > 1, "ARMRouter: INVALID_PATH");
            // amounts = new uint256[](path.length);
            // amounts[path.length - 1] = amountOut;
            // ---
            // Get length of the path array
            let pathLen := mload(path)
            // If path.length < 2, revert with error
            if lt(pathLen, 2) {
                // Store error signature in memory at 0x80 (arbitrary location)
                // bytes4(keccak256("INVALID_PATH")) → 0x01deb4d7
                mstore(0x80, 0x01deb4d7)
                // Revert with the error signature,
                // Need to handle better error revert message
                revert(0x9c, 0x04)
            }

            // Initialize the amounts array
            // amounts = new uint256[](path.length);
            // Get free memory pointer
            let ptr := mload(0x40)
            // Allocate length of the amounts array in memory at free memory pointer
            mstore(ptr, pathLen)
            // Update free memory pointer to account for the amounts array storage
            mstore(0x40, add(ptr, add(mul(pathLen, 0x20), 0x20)))
            // Set amounts to point to the newly allocated memory
            amounts := ptr

            //amounts[path.length - 1] = amountOut;
            mstore(sub(mload(0x40), 0x20), amountOut)
            //}

            // ---
            // The following assembly block is equivalent to:
            // Calculate required input amounts in reverse order
            // for (uint256 i = path.length - 1; i > 0; i--) {
            //    amounts[i - 1] = _getAmountIn(amounts[i], path[i - 1], path[i]);
            // }
            // ---
            for { let i := sub(pathLen, 1) } gt(i, 0) { i := sub(i, 1) } {
                let _amountIn
                let _amountOut := mload(add(add(amounts, 0x20), shl(5, i))) // amounts[i]
                let tokenA := mload(add(add(path, 0x20), shl(5, sub(i, 1)))) // path[i - 1]
                let tokenB := mload(add(add(path, 0x20), shl(5, i))) // path[i]
                {
                    let swapType
                    let addr
                    let priceSig

                    // ---
                    // The following assembly block is equivalent to:
                    // Config memory config = getConfigFor(tokenA, tokenB);
                    // ---
                    {
                        ptr := mload(0x40)
                        mstore(ptr, tokenA)
                        mstore(add(ptr, 0x20), configs.slot)
                        let innerSlot := keccak256(ptr, 0x40)
                        mstore(ptr, tokenB)
                        mstore(add(ptr, 0x20), innerSlot)
                        let packed := sload(keccak256(ptr, 0x40))
                        if iszero(packed) {
                            mstore(0x80, 0xe47e2d62) // bytes4(keccak256("ARMRouter: PATH_NOT_FOUND")) → 0xe47e2d62
                            revert(0x9c, 0x04) // Reads 4 bytes.
                        }

                        // Unpack swapType (lowest 8 bits) → enum is right-aligned
                        swapType := and(packed, 0xff)
                        // Unpack address (bits 8 → 167) → right-aligned (standard for address)
                        addr := and(shr(8, packed), 0xffffffffffffffffffffffffffffffffffffffff)
                        // Unpack priceSig (bits 200 → 231) → bytes4 must be left-aligned in memory
                        priceSig := shl(224, and(shr(200, packed), 0xffffffff))
                    }

                    // ---
                    // The following assembly block is equivalent to:
                    // _amountIn = getAmountIn(_amountOut, tokenA, tokenB);
                    // ---
                    {
                        // Inline assembly to optimize traderate fetching and amountIn calculation
                        // if (config.swapType == SwapType.ARM)
                        if iszero(swapType) {
                            // ---
                            // The following assembly block is equivalent to:
                            // IERC20 token0 = AbstractARM(config.addr).token0();
                            // ---
                            let token0 := 0
                            {
                                // Get free memory pointer
                                ptr := mload(0x40)

                                // Memory store function signature
                                // bytes4(keccak256("token0()")) → 0x0dfe1681
                                // It need to be left-aligned in memory for the call, because there is no arguments.
                                mstore(ptr, 0x0dfe168100000000000000000000000000000000000000000000000000000000)

                                // Make the staticcall to fetch token0
                                // using `ptr` for `argsOffset`, because we stored the function signature there
                                // using `0x04` for `argsSize`, because the function signature is 4 bytes
                                // using `ptr` for `retOffset`, to store the returned token0 value in memory. Reusing `ptr` saves gas.
                                // using `0x20` for `retSize`, because an address feats in 32 bytes
                                let success := staticcall(gas(), addr, ptr, 0x04, ptr, 0x20)

                                // Revert if the call failed
                                if iszero(success) {
                                    // Store error signature in memory at 0x80 (arbitrary location)
                                    // bytes4(keccak256("ARMRouter: GET_TOKEN0_FAIL")) → 0x572a7e6d
                                    mstore(0x80, 0x572a7e6d)
                                    // Revert with the error signature,
                                    // Need to handle better error revert message
                                    revert(0x9c, 0x04)
                                }
                                // Load the returned token0 address from memory into the `token0` variable
                                token0 := mload(ptr)
                            }

                            // ---
                            // The following assembly block is equivalent to:
                            // uint256 traderate = tokenA == address(token0)
                            //     ? AbstractARM(config.addr).traderate0()
                            //     : AbstractARM(config.addr).traderate1();
                            // ---
                            let traderate := 0

                            // if (tokenA == address(token0))
                            if eq(tokenA, token0) {
                                // Get free memory pointer
                                ptr := mload(0x40)

                                // Memory store function signature
                                // bytes4(keccak256("traderate0()")) → 0x45059a6b
                                // It need to be left-aligned in memory for the call, because there is no arguments.
                                mstore(ptr, 0x45059a6b00000000000000000000000000000000000000000000000000000000)

                                // Make the staticcall to fetch traderate0
                                // using `ptr` for `argsOffset`, because we stored the function signature there
                                // using `0x04` for `argsSize`, because the function signature is 4 bytes
                                // using `ptr` for `retOffset`, to store the returned traderate0 value in memory. Reusing `ptr` saves gas.
                                // using `0x20` for `retSize`, because a uint256 feats in 32 bytes
                                let success := staticcall(gas(), addr, ptr, 0x04, ptr, 0x20)

                                // Revert if the call failed
                                if iszero(success) {
                                    // Store error signature in memory at 0x80 (arbitrary location)
                                    // bytes4(keccak256("ARMRouter: GET_TRADERATE0_FAIL")) → 0xc10bcf53
                                    mstore(0x80, 0xc10bcf53)
                                    // Revert with the error signature,
                                    // Need to handle better error revert message
                                    revert(0x9c, 0x04) // Reads 4 bytes.
                                }
                                traderate := mload(ptr)
                            }

                            // else or if (tokenB == address(token0))
                            // This is not exactly an else statement, but in practice one of the two conditions must be true
                            if eq(tokenB, token0) {
                                // Get free memory pointer
                                ptr := mload(0x40)

                                // Memory store function signature
                                // bytes4(keccak256("traderate1()")) → 0xcf1de5d8
                                // It need to be left-aligned in memory for the call, because there is no arguments.
                                mstore(ptr, 0xcf1de5d800000000000000000000000000000000000000000000000000000000)

                                // Make the staticcall to fetch traderate1
                                // using `ptr` for `argsOffset`, because we stored the function signature there
                                // using `0x04` for `argsSize`, because the function signature is 4 bytes
                                // using `ptr` for `retOffset`, to store the returned traderate1 value in memory. Reusing `ptr` saves gas.
                                // using `0x20` for `retSize`, because a uint256 feats in 32 bytes
                                let success := staticcall(gas(), addr, ptr, 0x04, ptr, 0x20)

                                // Revert if the call failed
                                if iszero(success) {
                                    // Store error signature in memory at 0x80 (arbitrary location)
                                    // bytes4(keccak256("ARMRouter: GET_TRADERATE1_FAIL")) → 0xc2d1624a
                                    mstore(0x80, 0xc2d1624a)
                                    // Revert with the error signature,
                                    // Need to handle better error revert message
                                    revert(0x9c, 0x04) // Reads 4 bytes.
                                }
                                traderate := mload(ptr)
                            }

                            // ---
                            // The following assembly block is equivalent to:
                            // amountIn = ((amountOut * PRICE_SCALE) / traderate) + 3;
                            // ---
                            // Calculate required input amount
                            // Round up division. ceil(a/b) = (a + b - 1) / b
                            // Adding 3 to account for rounding errors
                            _amountIn := add(div(add(mul(_amountOut, PRICE_SCALE), sub(traderate, 1)), traderate), 3)
                        }

                        // else if (config.swapType == SwapType.WRAPPER)
                        if eq(swapType, 1) {
                            // ---
                            // The following assembly block is equivalent to:
                            // (bool success, bytes memory data) = config.addr.call(abi.encodeWithSelector(config.priceSig, amountOut));
                            // require(success, "ARMRouter: GET_TRADERATE_FAIL");
                            // amountIn = abi.decode(data, (uint256));
                            // amountIn += 1;
                            // ---

                            // Get free memory pointer
                            ptr := mload(0x40)

                            // Store function signature in memory
                            mstore(ptr, priceSig)
                            // Store amountOut argument in memory right after the function signature
                            mstore(add(ptr, 0x04), _amountOut)

                            // Make the staticcall to fetch traderate for wrapper
                            // using `ptr` for `argsOffset`, because we stored the function signature there
                            // using `0x24` for `argsSize`, because the function signature (4 bytes) + uint256 argument (32 bytes) = 36 bytes (0x24)
                            // using `ptr` for `retOffset`, to store the returned token0 value in memory. Reusing `ptr` saves gas.
                            // using `0x20` for `retSize`, because an address feats in 32 bytes
                            let success := staticcall(gas(), addr, ptr, 0x24, ptr, 0x20)

                            // Revert if the call failed
                            if iszero(success) {
                                // Store error signature in memory at 0x80 (arbitrary location)
                                // bytes4(keccak256("ARMRouter: GET_TRADERATE_FAIL")) → 0xad51ce0b
                                mstore(0x80, 0xad51ce0b)
                                // Revert with the error signature,
                                // Need to handle better error revert message
                                revert(0x9c, 0x04)
                            }

                            // Load the returned amountIn from memory
                            // Add 1 to account for rounding errors
                            _amountIn := add(mload(ptr), 1)
                        }
                    }
                }

                // Store the calculated amountIn in the amounts array
                mstore(add(amounts, shl(5, i)), _amountIn)
            }

            // ---
            // The following assembly block is equivalent to:
            // uint256 amount0 = amounts[0];
            // require(amount0 <= amountInMax, "ARMRouter: EXCESSIVE_INPUT");
            // IERC20(path[0]).transferFrom(msg.sender, address(this), amount0);
            // ---
            let amount0 := mload(add(amounts, 0x20))
            if lt(amount0, add(amountInMax, 1)) {
                mstore(0x80, 0x13e1d9f9) // bytes4(keccak256("ARMRouter: EXCESSIVE_INPUT")) → 0x13e1d9f9
                revert(0x9c, 0x04) // Reads 4 bytes.
            }

            ptr := mload(0x40)
            mstore(ptr, 0x23b872dd00000000000000000000000000000000000000000000000000000000) // bytes4(keccak256("transferFrom(address,address,uint256)")) → 0x23b872dd
            mstore(add(ptr, 0x04), caller()) // from (msg.sender)
            mstore(add(ptr, 0x24), address()) // to (this)
            mstore(add(ptr, 0x44), amount0) // amount
            let success := call(gas(), mload(add(path, 0x20)), 0, ptr, 0x64, 0, 0)
            if iszero(success) {
                // Store error signature in memory at 0x80 (arbitrary location)
                // bytes4(keccak256("ARMRouter: TRANSFER_FROM_FAILED")) → 0x98266a68
                mstore(0x80, 0x98266a68)
                // Revert with the error signature,
                // Need to handle better error revert message
                revert(0x9c, 0x04)
            }
        }

        // Perform the swaps along the path
        // using new assembly block to avoid stack too deep errors
        // ---
        // The following assembly block is equivalent to:
        // for (uint256 i; i < path.length - 1; i++) {
        //     // Cache token addresses to save gas
        //     address tokenA = path[i];
        //     address tokenB = path[i + 1];
        //
        //     // Get ARM or Wrapper config
        //     Config memory config = getConfigFor(tokenA, tokenB);
        //
        //     if (config.swapType == SwapType.ARM) {
        //         // Determine receiver address
        //         address receiver = i < path.length - 2 ? address(this) : to;
        //
        //         // Perform the ARM swap
        //         AbstractARM(config.addr)
        //             .swapTokensForExactTokens(IERC20(tokenA), IERC20(tokenB), amounts[i + 1], amounts[i], receiver);
        //     } else {
        //         // Call the Wrapper contract's wrap/unwrap function
        //         (bool success,) = config.addr.call(abi.encodeWithSelector(config.wrapSig, amounts.get(i)));
        //
        //         // Ensure the wrap/unwrap was successful
        //         require(success, "ARMRouter: WRAP_UNWRAP_FAILED");
        //
        //         // If this is the last swap, transfer to the recipient
        //         if (i == path.length - 2) IERC20(tokenB).transfer(to, amounts.get(i + 1));
        //     }
        // }
        // ---
        assembly {
            for { let i := 0 } lt(i, sub(mload(path), 1)) { i := add(i, 1) } {
                let tokenA := mload(add(add(path, 0x20), shl(5, i)))
                let tokenB := mload(add(add(path, 0x20), shl(5, add(i, 1))))
                let _amountInMax := mload(add(add(amounts, 0x20), shl(5, i)))
                let _amountOut := mload(add(add(amounts, 0x20), shl(5, add(i, 1))))
                let swapType
                let addr
                let wrapSig

                // ---
                // The following assembly block is equivalent to:
                // Config memory config = getConfigFor(tokenA, tokenB);
                // ---
                {
                    let ptr := mload(0x40)
                    mstore(ptr, tokenA)
                    mstore(add(ptr, 0x20), configs.slot)
                    let innerSlot := keccak256(ptr, 0x40)
                    mstore(ptr, tokenB)
                    mstore(add(ptr, 0x20), innerSlot)
                    let packed := sload(keccak256(ptr, 0x40))
                    if iszero(packed) {
                        mstore(0x80, 0xe47e2d62) // bytes4(keccak256("ARMRouter: PATH_NOT_FOUND")) → 0xe47e2d62
                        revert(0x9c, 0x04) // Reads 4 bytes.
                    }

                    // Unpack swapType (lowest 8 bits) → enum is right-aligned
                    swapType := and(packed, 0xff)
                    // Unpack address (bits 8 → 167) → right-aligned (standard for address)
                    addr := and(shr(8, packed), 0xffffffffffffffffffffffffffffffffffffffff)

                    // Unpack wrapSig (bits 168 → 199) → bytes4 must be left-aligned in memory
                    wrapSig := shl(224, and(shr(168, packed), 0xffffffff))
                }

                if iszero(swapType) {
                    let receiver
                    switch lt(i, sub(mload(path), 2))
                    case 1 { receiver := address() }
                    default { receiver := to }

                    let ptr := mload(0x40)
                    mstore(ptr, 0xf7d3180900000000000000000000000000000000000000000000000000000000) //bytes4(keccak256("swapTokensForExactTokens(address,address,uint256,uint256,address)")) → 0xf7d31809
                    mstore(add(ptr, 0x04), tokenA)
                    mstore(add(ptr, 0x24), tokenB)
                    mstore(add(ptr, 0x44), _amountOut)
                    mstore(add(ptr, 0x64), _amountInMax)
                    mstore(add(ptr, 0x84), receiver)

                    let success := call(gas(), addr, 0, ptr, 0xa4, 0, 0)
                    if iszero(success) {
                        // Store error signature in memory at 0x80 (arbitrary location)
                        // bytes4(keccak256("ARMRouter: ARM_SWAP_FAILED")) → 0x009befa8
                        mstore(0x80, 0x009befa8)
                        // Revert with the error signature,
                        // Need to handle better error revert message
                        revert(0x9c, 0x04)
                    }
                }

                if eq(swapType, 1) {
                    let ptr := mload(0x40)
                    mstore(ptr, wrapSig)
                    mstore(add(ptr, 0x04), _amountInMax)
                    let success := call(gas(), addr, 0, ptr, 0x24, 0, 0)
                    if iszero(success) {
                        // Store error signature in memory at 0x80 (arbitrary location)
                        // bytes4(keccak256("ARMRouter: WRAP_UNWRAP_FAILED")) → 0xe99b4d3c
                        mstore(0x80, 0xe99b4d3c)
                        // Revert with the error signature,
                        // Need to handle better error revert message
                        revert(0x9c, 0x04)
                    }

                    if eq(i, sub(mload(path), 2)) {
                        mstore(ptr, 0xa9059cbb00000000000000000000000000000000000000000000000000000000) // bytes4(keccak256("transfer(address,uint256)")) → 0xa9059cbb
                        mstore(add(ptr, 0x04), to)
                        mstore(add(ptr, 0x24), _amountOut)
                        success := call(gas(), tokenB, 0, ptr, 0x44, 0, 0)
                        if iszero(success) {
                            // Store error signature in memory at 0x80 (arbitrary location)
                            // bytes4(keccak256("ARMRouter: TRANSFER_FAILED")) → 0x86866d06
                            mstore(0x80, 0x86866d06)
                            // Revert with the error signature,
                            // Need to handle better error revert message
                            revert(0x9c, 0x04)
                        }
                    }
                }
            }
        }
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
        // Ensure the first token in the path is WETH
        require(path[0] == address(WETH), "ARMRouter: INVALID_PATH");

        // Wrap ETH to WETH
        WETH.deposit{value: msg.value}();

        // Perform the swaps along the path
        amounts = _swapExactTokenFor(msg.value, path, to);

        // Ensure the output amount meets the minimum requirement
        uint256 lastIndex;
        assembly {
            // lastIndex = amounts.length - 1
            lastIndex := sub(mload(amounts), 1)
        }
        require(amounts.get(lastIndex) >= amountOutMin, "ARMRouter: INSUFFICIENT_OUTPUT");
    }

    /// @notice Swaps an exact amount of input tokens for as much ETH as possible, along the route determined by the path.
    /// @param amountIn The exact amount of input tokens to swap.
    /// @param amountOutMin The minimum amount of ETH that must be received for the transaction not to revert.
    /// @param path An array of token addresses representing the swap path.
    /// @param to The address that will receive the ETH.
    /// @param deadline The timestamp by which the transaction must be completed.
    /// @return amounts An array of token amounts for each step in the swap path.
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        // Cache last index in list to save gas, path and amounts lengths are the same
        // Done in 2 operations to save gas
        uint256 lenMinusOne = path.length;
        assembly {
            lenMinusOne := sub(lenMinusOne, 1)
        }

        // Ensure the last token in the path is WETH
        require(path[lenMinusOne] == address(WETH), "ARMRouter: INVALID_PATH");

        // Transfer the input tokens from the sender to this contract
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        // Perform the swaps along the path
        amounts = _swapExactTokenFor(amountIn, path, address(this));

        // Ensure the output amount meets the minimum requirement
        require(amounts.get(lenMinusOne) >= amountOutMin, "ARMRouter: INSUFFICIENT_OUTPUT");

        // Unwrap WETH to ETH and transfer to the recipient
        WETH.withdraw(amounts.get(lenMinusOne));
        payable(to).transfer(amounts.get(lenMinusOne));
    }

    /// @notice Swaps as few ETH as possible to receive an exact amount of output tokens, along the route determined by the path.
    /// @param amountOut The exact amount of output tokens to receive.
    /// @param path An array of token addresses representing the swap path.
    /// @param to The address that will receive the output tokens.
    /// @param deadline The timestamp by which the transaction must be completed.
    /// @return amounts An array of token amounts for each step in the swap path.
    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        // Ensure the first token in the path is WETH
        require(path[0] == address(WETH), "ARMRouter: INVALID_PATH");

        // Calculate the required input amounts for the desired output
        amounts = _getAmountsIn(amountOut, path);

        // Cache amounts[0] to save gas
        uint256 amount0 = amounts.get(0);

        // Ensure the required input does not exceed the sent ETH
        require(amount0 <= msg.value, "ARMRouter: EXCESSIVE_INPUT");

        // Wrap ETH to WETH
        WETH.deposit{value: amount0}();

        // Perform the swaps along the path
        _swapsForExactTokens(amounts, path, to);

        // Refund any excess ETH to the sender
        if (msg.value > amount0) payable(msg.sender).transfer(msg.value - amount0);
    }

    /// @notice Swaps as few input tokens as possible to receive an exact amount of ETH, along the route determined by the path.
    /// @param amountOut The exact amount of ETH to receive.
    /// @param amountInMax The maximum amount of input tokens that can be used for the swap.
    /// @param path An array of token addresses representing the swap path.
    /// @param to The address that will receive the ETH.
    /// @param deadline The timestamp by which the transaction must be completed.
    /// @return amounts An array of token amounts for each step in the swap path.
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        // Cache last index in list to save gas, path and amounts lengths are the same
        // Done in 2 operations to save gas
        uint256 lenMinusOne = path.length;
        assembly {
            lenMinusOne := sub(lenMinusOne, 1)
        }
        // Ensure the last token in the path is WETH
        require(path[lenMinusOne] == address(WETH), "ARMRouter: INVALID_PATH");

        // Calculate the required input amounts for the desired output
        amounts = _getAmountsIn(amountOut, path);

        // Cache amounts[0] to save gas
        uint256 amount0 = amounts.get(0);
        // Ensure the required input does not exceed the maximum allowed
        require(amount0 <= amountInMax, "ARMRouter: EXCESSIVE_INPUT");

        // Transfer the input tokens from the sender to this contract
        IERC20(path[0]).transferFrom(msg.sender, address(this), amount0);

        // Perform the swaps along the path
        _swapsForExactTokens(amounts, path, address(this));

        // Cache last amount to save gas
        uint256 lastAmount = amounts.get(lenMinusOne);
        // Unwrap WETH to ETH and transfer to the recipient
        WETH.withdraw(lastAmount);
        payable(to).transfer(lastAmount);
    }

    ////////////////////////////////////////////////////
    ///                 Internal Logic
    ////////////////////////////////////////////////////
    /// @notice Internal function to perform swaps along the specified path.
    /// @param amountIn The amount of input tokens to swap.
    /// @param path The swap path as an array of token addresses.
    /// @param to The address that will receive the output tokens.
    /// @return amounts An array of token amounts for each step in the swap path.
    function _swapExactTokenFor(uint256 amountIn, address[] memory path, address to)
        internal
        returns (uint256[] memory amounts)
    {
        // Cache length to save gas
        uint256 len = path.length;

        // Initialize the amounts array
        amounts = DynamicArrayLib.malloc(len);
        amounts.set(0, amountIn);

        // Cache next index to save gas
        uint256 _next;
        // Cache length minus two to save gas
        uint256 lenMinusTwo;
        assembly {
            // lenMinusTwo = len - 2
            lenMinusTwo := sub(len, 2)
        }
        // Perform the swaps along the path
        for (uint256 i; i < len - 1; i++) {
            // Next token index
            assembly {
                // _next += 1
                _next := add(_next, 1)
            }

            // Cache token addresses to save gas
            address tokenA = path[i];
            address tokenB = path[_next];

            // Get ARM or Wrapper config
            Config memory config = getConfigFor(tokenA, tokenB);

            if (config.swapType == SwapType.ARM) {
                // Determine receiver address
                address receiver = i < lenMinusTwo ? address(this) : to;

                // Call the ARM contract's swap function
                uint256[] memory obtained = AbstractARM(config.addr)
                    .swapExactTokensForTokens(IERC20(tokenA), IERC20(tokenB), amounts.get(i), 0, receiver);

                // Perform the ARM swap
                amounts[_next] = obtained.get(1);
            } else {
                // Call the Wrapper contract's wrap/unwrap function
                (bool success, bytes memory data) =
                    config.addr.call(abi.encodeWithSelector(config.wrapSig, amounts.get(i)));

                // Ensure the wrap/unwrap was successful
                require(success, "ARMRouter: WRAP_UNWRAP_FAILED");

                // It's a wrap/unwrap operation
                amounts.set(_next, abi.decode(data, (uint256)));

                // If this is the last swap, transfer to the recipient
                if (i == lenMinusTwo) IERC20(tokenB).transfer(to, amounts.get(_next));
            }
        }
    }

    /// @notice Internal function to perform swaps for exact output amounts along the specified path.
    /// @param amounts The array of token amounts for each step in the swap path.
    /// @param path The swap path as an array of token addresses.
    /// @param to The address that will receive the output tokens.
    function _swapsForExactTokens(uint256[] memory amounts, address[] memory path, address to) internal {
        /*
        for (uint256 i; i < path.length - 1; i++) {
            // Cache token addresses to save gas
            address tokenA = path[i];
            address tokenB = path[i + 1];

            // Get ARM or Wrapper config
            Config memory config = getConfigFor(tokenA, tokenB);

            if (config.swapType == SwapType.ARM) {
                // Determine receiver address
                address receiver = i < path.length - 2 ? address(this) : to;

                // Perform the ARM swap
                AbstractARM(config.addr)
                    .swapTokensForExactTokens(IERC20(tokenA), IERC20(tokenB), amounts[i + 1], amounts[i], receiver);
            } else {
                // Call the Wrapper contract's wrap/unwrap function
                (bool success,) = config.addr.call(abi.encodeWithSelector(config.wrapSig, amounts.get(i)));

                // Ensure the wrap/unwrap was successful
                require(success, "ARMRouter: WRAP_UNWRAP_FAILED");

                // If this is the last swap, transfer to the recipient
                if (i == path.length - 2) IERC20(tokenB).transfer(to, amounts.get(i + 1));
            }
        }
        */
        assembly {
            for { let i := 0 } lt(i, sub(mload(path), 1)) { i := add(i, 1) } {
                let tokenA := mload(add(add(path, 0x20), shl(5, i)))
                let tokenB := mload(add(add(path, 0x20), shl(5, add(i, 1))))
                let _amountInMax := mload(add(add(amounts, 0x20), shl(5, i)))
                let _amountOut := mload(add(add(amounts, 0x20), shl(5, add(i, 1))))
                let swapType
                let addr
                let wrapSig

                // ---
                // The following assembly block is equivalent to:
                // Config memory config = getConfigFor(tokenA, tokenB);
                // ---
                {
                    let ptr := mload(0x40)
                    mstore(ptr, tokenA)
                    mstore(add(ptr, 0x20), configs.slot)
                    let innerSlot := keccak256(ptr, 0x40)
                    mstore(ptr, tokenB)
                    mstore(add(ptr, 0x20), innerSlot)
                    let packed := sload(keccak256(ptr, 0x40))
                    if iszero(packed) {
                        mstore(0x80, 0xe47e2d62) // bytes4(keccak256("ARMRouter: PATH_NOT_FOUND")) → 0xe47e2d62
                        revert(0x9c, 0x04) // Reads 4 bytes.
                    }

                    // Unpack swapType (lowest 8 bits) → enum is right-aligned
                    swapType := and(packed, 0xff)
                    // Unpack address (bits 8 → 167) → right-aligned (standard for address)
                    addr := and(shr(8, packed), 0xffffffffffffffffffffffffffffffffffffffff)

                    // Unpack wrapSig (bits 168 → 199) → bytes4 must be left-aligned in memory
                    wrapSig := shl(224, and(shr(168, packed), 0xffffffff))
                }

                if iszero(swapType) {
                    let receiver
                    switch lt(i, sub(mload(path), 2))
                    case 1 { receiver := address() }
                    default { receiver := to }

                    let ptr := mload(0x40)
                    mstore(ptr, 0xf7d3180900000000000000000000000000000000000000000000000000000000) //bytes4(keccak256("swapTokensForExactTokens(address,address,uint256,uint256,address)")) → 0xf7d31809
                    mstore(add(ptr, 0x04), tokenA)
                    mstore(add(ptr, 0x24), tokenB)
                    mstore(add(ptr, 0x44), _amountOut)
                    mstore(add(ptr, 0x64), _amountInMax)
                    mstore(add(ptr, 0x84), receiver)

                    let success := call(gas(), addr, 0, ptr, 0xa4, 0, 0)
                    if iszero(success) {
                        // Store error signature in memory at 0x80 (arbitrary location)
                        // bytes4(keccak256("ARMRouter: ARM_SWAP_FAILED")) → 0x009befa8
                        mstore(0x80, 0x009befa8)
                        // Revert with the error signature,
                        // Need to handle better error revert message
                        revert(0x9c, 0x04)
                    }
                }

                if eq(swapType, 1) {
                    let ptr := mload(0x40)
                    mstore(ptr, wrapSig)
                    mstore(add(ptr, 0x04), _amountInMax)
                    let success := call(gas(), addr, 0, ptr, 0x24, 0, 0)
                    if iszero(success) {
                        // Store error signature in memory at 0x80 (arbitrary location)
                        // bytes4(keccak256("ARMRouter: WRAP_UNWRAP_FAILED")) → 0xe99b4d3c
                        mstore(0x80, 0xe99b4d3c)
                        // Revert with the error signature,
                        // Need to handle better error revert message
                        revert(0x9c, 0x04)
                    }

                    if eq(i, sub(mload(path), 2)) {
                        mstore(ptr, 0xa9059cbb00000000000000000000000000000000000000000000000000000000) // bytes4(keccak256("transfer(address,uint256)")) → 0xa9059cbb
                        mstore(add(ptr, 0x04), to)
                        mstore(add(ptr, 0x24), _amountOut)
                        success := call(gas(), tokenB, 0, ptr, 0x44, 0, 0)
                        if iszero(success) {
                            // Store error signature in memory at 0x80 (arbitrary location)
                            // bytes4(keccak256("ARMRouter: TRANSFER_FAILED")) → 0x86866d06
                            mstore(0x80, 0x86866d06)
                            // Revert with the error signature,
                            // Need to handle better error revert message
                            revert(0x9c, 0x04)
                        }
                    }
                }
            }
        }
    }

    /// @notice Calculates the required input amounts for a desired output amount along the specified path.
    /// @param amountOut The desired output amount of the final token in the path.
    /// @param path The swap path as an array of token addresses.
    /// @return amounts An array of token amounts for each step in the swap path.
    function _getAmountsIn(uint256 amountOut, address[] memory path) internal returns (uint256[] memory amounts) {
        // ---
        // The following assembly block is equivalent to:
        // require(path.length > 1, "ARMRouter: INVALID_PATH");
        // amounts = new uint256[](path.length);
        // amounts[path.length - 1] = amountOut;
        // ---
        assembly {
            // If path.length < 2, revert with error
            if lt(mload(path), 2) {
                // Store error signature in memory at 0x80 (arbitrary location)
                // bytes4(keccak256("INVALID_PATH")) → 0x01deb4d7
                mstore(0x80, 0x01deb4d7)
                // Revert with the error signature,
                // Need to handle better error revert message
                revert(0x9c, 0x04)
            }

            // Initialize the amounts array
            // amounts = new uint256[](path.length);
            // Get length of the path array
            let len := mload(path)
            // Get free memory pointer
            let ptr := mload(0x40)
            // Allocate length of the amounts array in memory at free memory pointer
            mstore(ptr, len)
            // Update free memory pointer to account for the amounts array storage
            mstore(0x40, add(ptr, add(mul(len, 0x20), 0x20)))
            // Set amounts to point to the newly allocated memory
            amounts := ptr

            //amounts[path.length - 1] = amountOut;
            mstore(sub(mload(0x40), 0x20), amountOut)
        }

        // ---
        // The following assembly block is equivalent to:
        // Calculate required input amounts in reverse order
        // for (uint256 i = path.length - 1; i > 0; i--) {
        //    amounts[i - 1] = _getAmountIn(amounts[i], path[i - 1], path[i]);
        // }
        // ---
        assembly {
            for { let i := sub(mload(path), 1) } gt(i, 0) { i := sub(i, 1) } {
                let _amountIn
                let _amountOut := mload(add(add(amounts, 0x20), shl(5, i))) // amounts[i]
                let tokenA := mload(add(add(path, 0x20), shl(5, sub(i, 1)))) // path[i - 1]
                let tokenB := mload(add(add(path, 0x20), shl(5, i))) // path[i]
                {
                    let swapType
                    let addr
                    let priceSig

                    // ---
                    // The following assembly block is equivalent to:
                    // Config memory config = getConfigFor(tokenA, tokenB);
                    // ---
                    {
                        let ptr := mload(0x40)
                        mstore(ptr, tokenA)
                        mstore(add(ptr, 0x20), configs.slot)
                        let innerSlot := keccak256(ptr, 0x40)
                        mstore(ptr, tokenB)
                        mstore(add(ptr, 0x20), innerSlot)
                        let packed := sload(keccak256(ptr, 0x40))
                        if iszero(packed) {
                            mstore(0x80, 0xe47e2d62) // bytes4(keccak256("ARMRouter: PATH_NOT_FOUND")) → 0xe47e2d62
                            revert(0x9c, 0x04) // Reads 4 bytes.
                        }

                        // Unpack swapType (lowest 8 bits) → enum is right-aligned
                        swapType := and(packed, 0xff)
                        // Unpack address (bits 8 → 167) → right-aligned (standard for address)
                        addr := and(shr(8, packed), 0xffffffffffffffffffffffffffffffffffffffff)

                        // Unpack priceSig (bits 200 → 231) → bytes4 must be left-aligned in memory
                        priceSig := shl(224, and(shr(200, packed), 0xffffffff))
                    }

                    // ---
                    // The following assembly block is equivalent to:
                    // _amountIn = getAmountIn(_amountOut, tokenA, tokenB);
                    // ---
                    {
                        // Inline assembly to optimize traderate fetching and amountIn calculation
                        // if (config.swapType == SwapType.ARM)
                        if iszero(swapType) {
                            // ---
                            // The following assembly block is equivalent to:
                            // IERC20 token0 = AbstractARM(config.addr).token0();
                            // ---
                            let token0 := 0
                            {
                                // Get free memory pointer
                                let ptr := mload(0x40)

                                // Memory store function signature
                                // bytes4(keccak256("token0()")) → 0x0dfe1681
                                // It need to be left-aligned in memory for the call, because there is no arguments.
                                mstore(ptr, 0x0dfe168100000000000000000000000000000000000000000000000000000000)

                                // Make the staticcall to fetch token0
                                // using `ptr` for `argsOffset`, because we stored the function signature there
                                // using `0x04` for `argsSize`, because the function signature is 4 bytes
                                // using `ptr` for `retOffset`, to store the returned token0 value in memory. Reusing `ptr` saves gas.
                                // using `0x20` for `retSize`, because an address feats in 32 bytes
                                let success := staticcall(gas(), addr, ptr, 0x04, ptr, 0x20)

                                // Revert if the call failed
                                if iszero(success) {
                                    // Store error signature in memory at 0x80 (arbitrary location)
                                    // bytes4(keccak256("ARMRouter: GET_TOKEN0_FAIL")) → 0x572a7e6d
                                    mstore(0x80, 0x572a7e6d)
                                    // Revert with the error signature,
                                    // Need to handle better error revert message
                                    revert(0x9c, 0x04)
                                }
                                // Load the returned token0 address from memory into the `token0` variable
                                token0 := mload(ptr)
                            }

                            // ---
                            // The following assembly block is equivalent to:
                            // uint256 traderate = tokenA == address(token0)
                            //     ? AbstractARM(config.addr).traderate0()
                            //     : AbstractARM(config.addr).traderate1();
                            // ---
                            let traderate := 0

                            // if (tokenA == address(token0))
                            if eq(tokenA, token0) {
                                // Get free memory pointer
                                let ptr := mload(0x40)

                                // Memory store function signature
                                // bytes4(keccak256("traderate0()")) → 0x45059a6b
                                // It need to be left-aligned in memory for the call, because there is no arguments.
                                mstore(ptr, 0x45059a6b00000000000000000000000000000000000000000000000000000000)

                                // Make the staticcall to fetch traderate0
                                // using `ptr` for `argsOffset`, because we stored the function signature there
                                // using `0x04` for `argsSize`, because the function signature is 4 bytes
                                // using `ptr` for `retOffset`, to store the returned traderate0 value in memory. Reusing `ptr` saves gas.
                                // using `0x20` for `retSize`, because a uint256 feats in 32 bytes
                                let success := staticcall(gas(), addr, ptr, 0x04, ptr, 0x20)

                                // Revert if the call failed
                                if iszero(success) {
                                    // Store error signature in memory at 0x80 (arbitrary location)
                                    // bytes4(keccak256("ARMRouter: GET_TRADERATE0_FAIL")) → 0xc10bcf53
                                    mstore(0x80, 0xc10bcf53)
                                    // Revert with the error signature,
                                    // Need to handle better error revert message
                                    revert(0x9c, 0x04) // Reads 4 bytes.
                                }
                                traderate := mload(ptr)
                            }

                            // else or if (tokenB == address(token0))
                            // This is not exactly an else statement, but in practice one of the two conditions must be true
                            if eq(tokenB, token0) {
                                // Get free memory pointer
                                let ptr := mload(0x40)

                                // Memory store function signature
                                // bytes4(keccak256("traderate1()")) → 0xcf1de5d8
                                // It need to be left-aligned in memory for the call, because there is no arguments.
                                mstore(ptr, 0xcf1de5d800000000000000000000000000000000000000000000000000000000)

                                // Make the staticcall to fetch traderate1
                                // using `ptr` for `argsOffset`, because we stored the function signature there
                                // using `0x04` for `argsSize`, because the function signature is 4 bytes
                                // using `ptr` for `retOffset`, to store the returned traderate1 value in memory. Reusing `ptr` saves gas.
                                // using `0x20` for `retSize`, because a uint256 feats in 32 bytes
                                let success := staticcall(gas(), addr, ptr, 0x04, ptr, 0x20)

                                // Revert if the call failed
                                if iszero(success) {
                                    // Store error signature in memory at 0x80 (arbitrary location)
                                    // bytes4(keccak256("ARMRouter: GET_TRADERATE1_FAIL")) → 0xc2d1624a
                                    mstore(0x80, 0xc2d1624a)
                                    // Revert with the error signature,
                                    // Need to handle better error revert message
                                    revert(0x9c, 0x04) // Reads 4 bytes.
                                }
                                traderate := mload(ptr)
                            }

                            // ---
                            // The following assembly block is equivalent to:
                            // amountIn = ((amountOut * PRICE_SCALE) / traderate) + 3;
                            // ---
                            // Calculate required input amount
                            // Round up division. ceil(a/b) = (a + b - 1) / b
                            // Adding 3 to account for rounding errors
                            _amountIn := add(div(add(mul(_amountOut, PRICE_SCALE), sub(traderate, 1)), traderate), 3)
                        }

                        // else if (config.swapType == SwapType.WRAPPER)
                        if eq(swapType, 1) {
                            // ---
                            // The following assembly block is equivalent to:
                            // (bool success, bytes memory data) = config.addr.call(abi.encodeWithSelector(config.priceSig, amountOut));
                            // require(success, "ARMRouter: GET_TRADERATE_FAIL");
                            // amountIn = abi.decode(data, (uint256));
                            // amountIn += 1;
                            // ---

                            // Get free memory pointer
                            let ptr := mload(0x40)

                            // Store function signature in memory
                            mstore(ptr, priceSig)
                            // Store amountOut argument in memory right after the function signature
                            mstore(add(ptr, 0x04), _amountOut)

                            // Make the staticcall to fetch traderate for wrapper
                            // using `ptr` for `argsOffset`, because we stored the function signature there
                            // using `0x24` for `argsSize`, because the function signature (4 bytes) + uint256 argument (32 bytes) = 36 bytes (0x24)
                            // using `ptr` for `retOffset`, to store the returned token0 value in memory. Reusing `ptr` saves gas.
                            // using `0x20` for `retSize`, because an address feats in 32 bytes
                            let success := staticcall(gas(), addr, ptr, 0x24, ptr, 0x20)

                            // Revert if the call failed
                            if iszero(success) {
                                // Store error signature in memory at 0x80 (arbitrary location)
                                // bytes4(keccak256("ARMRouter: GET_TRADERATE_FAIL")) → 0xad51ce0b
                                mstore(0x80, 0xad51ce0b)
                                // Revert with the error signature,
                                // Need to handle better error revert message
                                revert(0x9c, 0x04)
                            }

                            // Load the returned amountIn from memory
                            // Add 1 to account for rounding errors
                            _amountIn := add(mload(ptr), 1)
                        }
                    }
                }

                // Store the calculated amountIn in the amounts array
                mstore(add(amounts, shl(5, i)), _amountIn)
            }
        }
    }

    /// @notice Calculates the required input amount for a desired output amount between two tokens.
    /// @param amountOut The desired output amount.
    /// @param tokenA The address of the input token.
    /// @param tokenB The address of the output token.
    /// @return amountIn The required input amount.
    function _getAmountIn(uint256 amountOut, address tokenA, address tokenB) internal returns (uint256 amountIn) {
        assembly {
            let swapType
            let addr
            let priceSig
            {
                let ptr := mload(0x40)
                mstore(ptr, tokenA)
                mstore(add(ptr, 0x20), configs.slot)
                let innerSlot := keccak256(ptr, 0x40)
                mstore(ptr, tokenB)
                mstore(add(ptr, 0x20), innerSlot)
                let packed := sload(keccak256(ptr, 0x40))
                if iszero(packed) {
                    mstore(0x80, 0xe47e2d62) // bytes4(keccak256("ARMRouter: PATH_NOT_FOUND")) → 0xe47e2d62
                    revert(0x9c, 0x04) // Reads 4 bytes.
                }

                // Unpack swapType (lowest 8 bits) → enum is right-aligned
                swapType := and(packed, 0xff)
                // Unpack address (bits 8 → 167) → right-aligned (standard for address)
                addr := and(shr(8, packed), 0xffffffffffffffffffffffffffffffffffffffff)

                // Unpack priceSig (bits 200 → 231) → bytes4 must be left-aligned in memory
                priceSig := shl(224, and(shr(200, packed), 0xffffffff))
            }

            // Inline assembly to optimize traderate fetching and amountIn calculation
            // if (config.swapType == SwapType.ARM)
            if iszero(swapType) {
                // ---
                // The following assembly block is equivalent to:
                // IERC20 token0 = AbstractARM(config.addr).token0();
                // ---
                let token0 := 0
                {
                    // Get free memory pointer
                    let ptr := mload(0x40)

                    // Memory store function signature
                    // bytes4(keccak256("token0()")) → 0x0dfe1681
                    // It need to be left-aligned in memory for the call, because there is no arguments.
                    mstore(ptr, 0x0dfe168100000000000000000000000000000000000000000000000000000000)

                    // Make the staticcall to fetch token0
                    // using `ptr` for `argsOffset`, because we stored the function signature there
                    // using `0x04` for `argsSize`, because the function signature is 4 bytes
                    // using `ptr` for `retOffset`, to store the returned token0 value in memory. Reusing `ptr` saves gas.
                    // using `0x20` for `retSize`, because an address feats in 32 bytes
                    let success := staticcall(gas(), addr, ptr, 0x04, ptr, 0x20)

                    // Revert if the call failed
                    if iszero(success) {
                        // Store error signature in memory at 0x80 (arbitrary location)
                        // bytes4(keccak256("ARMRouter: GET_TOKEN0_FAIL")) → 0x572a7e6d
                        mstore(0x80, 0x572a7e6d)
                        // Revert with the error signature,
                        // Need to handle better error revert message
                        revert(0x9c, 0x04)
                    }
                    // Load the returned token0 address from memory into the `token0` variable
                    token0 := mload(ptr)
                }

                // ---
                // The following assembly block is equivalent to:
                // uint256 traderate = tokenA == address(token0)
                //     ? AbstractARM(config.addr).traderate0()
                //     : AbstractARM(config.addr).traderate1();
                // ---
                let traderate := 0

                // if (tokenA == address(token0))
                if eq(tokenA, token0) {
                    // Get free memory pointer
                    let ptr := mload(0x40)

                    // Memory store function signature
                    // bytes4(keccak256("traderate0()")) → 0x45059a6b
                    // It need to be left-aligned in memory for the call, because there is no arguments.
                    mstore(ptr, 0x45059a6b00000000000000000000000000000000000000000000000000000000)

                    // Make the staticcall to fetch traderate0
                    // using `ptr` for `argsOffset`, because we stored the function signature there
                    // using `0x04` for `argsSize`, because the function signature is 4 bytes
                    // using `ptr` for `retOffset`, to store the returned traderate0 value in memory. Reusing `ptr` saves gas.
                    // using `0x20` for `retSize`, because a uint256 feats in 32 bytes
                    let success := staticcall(gas(), addr, ptr, 0x04, ptr, 0x20)

                    // Revert if the call failed
                    if iszero(success) {
                        // Store error signature in memory at 0x80 (arbitrary location)
                        // bytes4(keccak256("ARMRouter: GET_TRADERATE0_FAIL")) → 0xc10bcf53
                        mstore(0x80, 0xc10bcf53)
                        // Revert with the error signature,
                        // Need to handle better error revert message
                        revert(0x9c, 0x04) // Reads 4 bytes.
                    }
                    traderate := mload(ptr)
                }

                // else or if (tokenB == address(token0))
                // This is not exactly an else statement, but in practice one of the two conditions must be true
                if eq(tokenB, token0) {
                    // Get free memory pointer
                    let ptr := mload(0x40)

                    // Memory store function signature
                    // bytes4(keccak256("traderate1()")) → 0xcf1de5d8
                    // It need to be left-aligned in memory for the call, because there is no arguments.
                    mstore(ptr, 0xcf1de5d800000000000000000000000000000000000000000000000000000000)

                    // Make the staticcall to fetch traderate1
                    // using `ptr` for `argsOffset`, because we stored the function signature there
                    // using `0x04` for `argsSize`, because the function signature is 4 bytes
                    // using `ptr` for `retOffset`, to store the returned traderate1 value in memory. Reusing `ptr` saves gas.
                    // using `0x20` for `retSize`, because a uint256 feats in 32 bytes
                    let success := staticcall(gas(), addr, ptr, 0x04, ptr, 0x20)

                    // Revert if the call failed
                    if iszero(success) {
                        // Store error signature in memory at 0x80 (arbitrary location)
                        // bytes4(keccak256("ARMRouter: GET_TRADERATE1_FAIL")) → 0xc2d1624a
                        mstore(0x80, 0xc2d1624a)
                        // Revert with the error signature,
                        // Need to handle better error revert message
                        revert(0x9c, 0x04) // Reads 4 bytes.
                    }
                    traderate := mload(ptr)
                }

                // ---
                // The following assembly block is equivalent to:
                // amountIn = ((amountOut * PRICE_SCALE) / traderate) + 3;
                // ---
                // Calculate required input amount
                // Round up division. ceil(a/b) = (a + b - 1) / b
                // Adding 3 to account for rounding errors
                amountIn := add(div(add(mul(amountOut, PRICE_SCALE), sub(traderate, 1)), traderate), 3)
            }

            // else if (config.swapType == SwapType.WRAPPER)
            if eq(swapType, 1) {
                // ---
                // The following assembly block is equivalent to:
                // (bool success, bytes memory data) = config.addr.call(abi.encodeWithSelector(config.priceSig, amountOut));
                // require(success, "ARMRouter: GET_TRADERATE_FAIL");
                // amountIn = abi.decode(data, (uint256));
                // amountIn += 1;
                // ---

                // Get free memory pointer
                let ptr := mload(0x40)

                // Store function signature in memory
                mstore(ptr, priceSig)
                // Store amountOut argument in memory right after the function signature
                mstore(add(ptr, 0x04), amountOut)

                // Make the staticcall to fetch traderate for wrapper
                // using `ptr` for `argsOffset`, because we stored the function signature there
                // using `0x24` for `argsSize`, because the function signature (4 bytes) + uint256 argument (32 bytes) = 36 bytes (0x24)
                // using `ptr` for `retOffset`, to store the returned token0 value in memory. Reusing `ptr` saves gas.
                // using `0x20` for `retSize`, because an address feats in 32 bytes
                let success := staticcall(gas(), addr, ptr, 0x24, ptr, 0x20)

                // Revert if the call failed
                if iszero(success) {
                    // Store error signature in memory at 0x80 (arbitrary location)
                    // bytes4(keccak256("ARMRouter: GET_TRADERATE_FAIL")) → 0xad51ce0b
                    mstore(0x80, 0xad51ce0b)
                    // Revert with the error signature,
                    // Need to handle better error revert message
                    revert(0x9c, 0x04)
                }

                // Load the returned amountIn from memory
                // Add 1 to account for rounding errors
                amountIn := add(mload(ptr), 1)
            }
        }
    }

    ////////////////////////////////////////////////////
    ///                 View Functions
    ////////////////////////////////////////////////////
    /// @notice Retrieves the ARM or Wrapper configuration for a given token pair.
    /// @param tokenA The address of the first token.
    /// @param tokenB The address of the second token.
    /// @return config The configuration struct containing swap type, address, and function signatures.
    function getConfigFor(address tokenA, address tokenB) public view returns (Config memory config) {
        // Fetch the ARM configuration for the token pair
        // The following assembly block efficiently computes the storage slot for configs[tokenA][tokenB]
        // ~~ config = configs[tokenA][tokenB];
        assembly {
            // Temporary memory pointer for keccak256 calculations
            let ptr := mload(0x40)

            // Compute inner mapping slot: mapping(address => mapping(...))[from]
            mstore(ptr, tokenA)
            mstore(add(ptr, 0x20), configs.slot)
            let innerSlot := keccak256(ptr, 0x40)

            // Compute final storage slot: mapping(address => Config)[to] inside the inner mapping
            mstore(ptr, tokenB)
            mstore(add(ptr, 0x20), innerSlot)
            let slot := keccak256(ptr, 0x40)

            // Load the single packed storage slot (29 bytes → fits in one word)
            let packed := sload(slot)

            // Optional: early return if route doesn't exist
            if iszero(packed) {
                mstore(0x80, 0xe47e2d62) // bytes4(keccak256("ARMRouter: PATH_NOT_FOUND")) → 0xe47e2d62
                revert(0x9c, 0x04) // Reads 4 bytes.
            }

            // Allocate memory for the returned struct (4 full slots)
            config := mload(0x40)
            mstore(0x40, add(config, 0x80)) // advance free memory pointer

            // Unpack swapType (lowest 8 bits) → enum is right-aligned
            mstore(config, and(packed, 0xff))

            // Unpack address (bits 8 → 167) → right-aligned (standard for address)
            mstore(add(config, 0x20), and(shr(8, packed), 0xffffffffffffffffffffffffffffffffffffffff))

            // Unpack wrapSig (bits 168 → 199) → bytes4 must be left-aligned in memory
            let wrapSig := and(shr(168, packed), 0xffffffff)
            mstore(add(config, 0x40), shl(224, wrapSig))

            // Unpack priceSig (bits 200 → 231) → bytes4 must be left-aligned in memory
            let priceSig := and(shr(200, packed), 0xffffffff)
            mstore(add(config, 0x60), shl(224, priceSig))
        }
    }

    ////////////////////////////////////////////////////
    ///                 Owner Functions
    ////////////////////////////////////////////////////
    /// @notice Registers a new ARM or Wrapper configuration for a given token pair.
    /// @param tokenA The address of the first token.
    /// @param tokenB The address of the second token.
    /// @param swapType The type of swap (ARM or Wrapper).
    /// @param addr The address of the ARM or Wrapper contract.
    /// @param wrapSig The function signature for wrap/unwrap operations (only for Wrapper).
    /// @param priceSig The function signature for price queries on wrappers (only for Wrapper).
    function registerConfig(
        address tokenA,
        address tokenB,
        SwapType swapType,
        address addr,
        bytes4 wrapSig,
        bytes4 priceSig
    ) external onlyOwner {
        // Max approval for router to interact with ARMs
        IERC20(tokenA).approve(addr, type(uint256).max);

        // Store the ARM configuration
        configs[tokenA][tokenB] = Config({swapType: swapType, addr: addr, wrapSig: wrapSig, priceSig: priceSig});
    }

    receive() external payable {}
}
