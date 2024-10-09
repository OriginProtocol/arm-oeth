// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Vm} from "forge-std/Vm.sol";

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract MockSTETH is ERC20 {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////
    uint256 public sum_of_errors;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor() ERC20("Liquid staked Ether 2.0", "stETH", 18) {}

    //////////////////////////////////////////////////////
    /// --- FUNCTIONS
    //////////////////////////////////////////////////////
    function transfer(address to, uint256 amount) public override returns (bool) {
        return super.transfer(to, brutalizeAmount(amount));
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        return super.transferFrom(from, to, brutalizeAmount(amount));
    }

    function brutalizeAmount(uint256 amount) public returns (uint256) {
        // Only brutalize the sender doesn't sent all of their balance
        if (balanceOf[msg.sender] != amount && amount > 0) {
            // Get a random number between 0 and 1
            uint256 randomUint = vm.randomUint(0, 1);
            // If the amount is greater than the random number, subtract the random number from the amount
            if (amount > randomUint) {
                amount -= randomUint;
                sum_of_errors += randomUint;
            }
        }
        return amount;
    }
}
