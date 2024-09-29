// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {console} from "forge-std/Console.sol";

// Handlers
import {BaseHandler} from "./BaseHandler.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";

/// @notice LpHandler contract
/// @dev This contract is used to handle all functionnalities related to providing liquidity in the ARM.
contract LpHandler is BaseHandler {
    ////////////////////////////////////////////////////
    /// --- CONSTANTS && IMMUTABLES
    ////////////////////////////////////////////////////
    IERC20 public immutable weth;
    LidoARM public immutable arm;

    ////////////////////////////////////////////////////
    /// --- VARIABLES
    ////////////////////////////////////////////////////
    address[] public lps; // Users that provide liquidity

    ////////////////////////////////////////////////////
    /// --- VARIABLES FOR INVARIANT ASSERTIONS
    ////////////////////////////////////////////////////
    uint256 public sum_of_deposits;

    ////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////
    constructor(address _arm, address _weth, address[] memory _lps) {
        arm = LidoARM(payable(_arm));
        weth = IERC20(_weth);

        require(_lps.length > 0, "LH: EMPTY_LPS");
        lps = _lps;
    }

    ////////////////////////////////////////////////////
    /// --- ACTIONS
    ////////////////////////////////////////////////////
    /// @notice Provide liquidity to the ARM with a given amount of WETH
    /// @dev This assumes that lps have unlimited capacity to provide liquidity on LPC contracts.
    function deposit(uint256 _seed) external {
        console.log("LpHandler.deposit(%d)", _seed);

        numberOfCalls["lpHandler.deposit"]++;

        // Get a user
        address user = lps[_seed % lps.length];

        // Amount of WETH to deposit should be between 0 and total WETH balance
        uint256 amount = _bound(_seed, 0, weth.balanceOf(user));

        // Prank user
        vm.startPrank(user);

        // Approve WETH to ARM
        weth.approve(address(arm), amount);

        // Deposit WETH
        arm.deposit(amount);

        // End prank
        vm.stopPrank();

        // Update sum of deposits
        sum_of_deposits += amount;
    }
}
