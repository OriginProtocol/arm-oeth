// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "contracts/Interfaces.sol";
import {ERC20, MockERC4626} from "dependencies/solmate-6.7.0/src/test/utils/mocks/MockERC4626.sol";

contract MockERC4626Market is MockERC4626 {
    constructor(IERC20 _token)
        MockERC4626(
            ERC20(address(_token)),
            string(abi.encode("MockERC4626", ERC20(address(_token)).name())),
            string(abi.encode("MockERC4626", ERC20(address(_token)).symbol()))
        )
    {}
}
