// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PeggedARM} from "./PeggedARM.sol";
import {OethLiquidityManager} from "./OethLiquidityManager.sol";

contract OEthARM is PeggedARM, OethLiquidityManager {
    /// @param _oeth The address of the OETH token that is being swapped into this contract.
    /// @param _weth The address of the WETH token that is being swapped out of this contract.
    constructor(address _oeth, address _weth, address _oethVault)
        PeggedARM(_oeth, _weth)
        OethLiquidityManager(_oethVault)
    {}
}
