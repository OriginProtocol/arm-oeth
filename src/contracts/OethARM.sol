// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PeggedARM} from "./PeggedARM.sol";
import {OethLiquidityManager} from "./OethLiquidityManager.sol";

contract OEthARM is PeggedARM, OethLiquidityManager {
    address constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor() PeggedARM(OETH, WETH) {}
}
