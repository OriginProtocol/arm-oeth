// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {console} from "forge-std/Console.sol";

// Handlers
import {BaseHandler} from "./BaseHandler.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";

/// @notice DonaitonHandler contract
/// @dev This contract is used to simulate donation of stETH or wETH to the ARM.
contract DonationHandler is BaseHandler {
    ////////////////////////////////////////////////////
    /// --- CONSTANTS && IMMUTABLES
    ////////////////////////////////////////////////////
    IERC20 public immutable weth;
    IERC20 public immutable steth;
    LidoARM public immutable arm;

    ////////////////////////////////////////////////////
    /// --- VARIABLES
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    /// --- VARIABLES FOR INVARIANT ASSERTIONS
    ////////////////////////////////////////////////////
    uint256 public sum_of_weth_donated;
    uint256 public sum_of_steth_donated;

    ////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////
    constructor(address _arm, address _weth, address _steth) {
        arm = LidoARM(payable(_arm));
        weth = IERC20(_weth);
        steth = IERC20(_steth);

        names[address(weth)] = "WETH";
        names[address(steth)] = "STETH";
    }

    ////////////////////////////////////////////////////
    /// --- ACTIONS
    ////////////////////////////////////////////////////
    function donateStETH(uint256 _seed) external {
        numberOfCalls["donationHandler.donateStETH"]++;

        uint256 amount = _bound(_seed, 1, 1 ether);
        console.log("DonationHandler.donateStETH(%18e)", amount);

        deal(address(steth), address(this), amount);

        steth.transfer(address(arm), amount);

        sum_of_steth_donated += amount;
    }

    function donateWETH(uint256 _seed) external {
        numberOfCalls["donationHandler.donateWETH"]++;

        uint256 amount = _bound(_seed, 1, 1 ether);
        console.log("DonationHandler.donateWETH(%18e)", amount);

        deal(address(weth), address(this), amount);

        weth.transfer(address(arm), amount);

        sum_of_weth_donated += amount;
    }
}
