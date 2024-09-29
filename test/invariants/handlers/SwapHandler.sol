// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {console} from "forge-std/Console.sol";

// Handlers
import {BaseHandler} from "./BaseHandler.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";

/// @notice SwapHandler contract
/// @dev This contract is used to handle all functionnalities related to the swap in the ARM.
contract SwapHandler is BaseHandler {
    ////////////////////////////////////////////////////
    /// --- CONSTANTS && IMMUTABLES
    ////////////////////////////////////////////////////
    IERC20 public immutable weth;
    IERC20 public immutable steth;
    LidoARM public immutable arm;

    ////////////////////////////////////////////////////
    /// --- VARIABLES
    ////////////////////////////////////////////////////
    address[] public swaps; // Users that perform swap

    ////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////
    constructor(address _arm, address _weth, address _steth, address[] memory _swaps) {
        arm = LidoARM(payable(_arm));
        weth = IERC20(_weth);
        steth = IERC20(_steth);

        swaps = _swaps;
    }

    ////////////////////////////////////////////////////
    /// --- ACTIONS
    ////////////////////////////////////////////////////
}
