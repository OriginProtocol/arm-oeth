// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "contracts/Interfaces.sol";
import {ERC20, MockERC4626} from "dependencies/solmate-6.7.0/src/test/utils/mocks/MockERC4626.sol";

contract MockMarket is MockERC4626 {
    constructor(IERC20 _token) MockERC4626(ERC20(address(_token)), "MockERC4626", "MockERC4626") {}
}
