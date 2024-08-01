// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Base_Test_} from "test/Base.sol";

abstract contract Helpers is Base_Test_ {
    /// @notice Override `deal()` function to handle OETH special case.
    function deal(address token, address to, uint256 amount) internal override {
        // Handle OETH special case, as rebasing tokens are not supported by the VM.
        if (token == address(oeth)) {
            address oethWhale = resolver.resolve("WHALE_OETH");
            // Check than whale as enough OETH.
            require(oeth.balanceOf(oethWhale) >= amount, "Fork_Shared_Test_: Not enough OETH in WHALE_OETH");

            // Transfer OETH from WHALE_OETH to the user.
            vm.prank(oethWhale);
            oeth.transfer(to, amount);
        } else {
            super.deal(token, to, amount);
        }
    }
}
