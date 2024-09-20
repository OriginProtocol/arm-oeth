// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Base_Test_} from "test/Base.sol";

abstract contract Helpers is Base_Test_ {
    /// @notice Override `deal()` function to handle OETH special case.
    function deal(address token, address to, uint256 amount) internal override {
        // Handle OETH special case, as rebasing tokens are not supported by the VM.
        if (token == address(oeth)) {
            // Check than whale as enough OETH.
            require(oeth.balanceOf(oethWhale) >= amount, "Fork_Shared_Test_: Not enough OETH in WHALE_OETH");

            // Transfer OETH from WHALE_OETH to the user.
            vm.prank(oethWhale);
            oeth.transfer(to, amount);
        } else if (token == address(steth)) {
            // Check than whale as enough stETH. Whale is wsteth contract.
            require(steth.balanceOf(address(wsteth)) >= amount, "Fork_Shared_Test_: Not enough stETH in WHALE_stETH");

            if (amount == 0) {
                vm.prank(to);
                steth.transfer(address(0x1), steth.balanceOf(to));
            } else {
                // Transfer stETH from WHALE_stETH to the user.
                vm.prank(address(wsteth));
                steth.transfer(to, amount);
            }
        } else {
            super.deal(token, to, amount);
        }
    }
}
