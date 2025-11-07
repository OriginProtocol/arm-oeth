// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Concrete_ARMRouter_SwapExactTokensForTokens_Test} from "./shared/SwapExactTokensForTokens.t.sol";
import {Unit_Concrete_ARMRouter_SwapTokensForExactTokens_Test} from "./shared/SwapTokensForExactTokens.t.sol";

import {WETH} from "@solmate/tokens/WETH.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

contract Unit_Concrete_ARMRouter_Swaps_Test is
    Unit_Concrete_ARMRouter_SwapExactTokensForTokens_Test,
    Unit_Concrete_ARMRouter_SwapTokensForExactTokens_Test
{
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();
        deal(address(this), 2_200 ether);
        WETH(payable(address(weth))).deposit{value: 2_200 ether}();

        // Fund ARMs with liquidity
        MockERC20(address(steth)).mint(address(lidoARM), 1_000 ether);
        MockERC20(address(eeth)).mint(address(etherfiARM), 1_000 ether);
        weth.transfer(address(lidoARM), 1_000 ether);
        weth.transfer(address(etherfiARM), 1_000 ether);

        // Fund this contract with tokens
        MockERC20(address(steth)).mint(address(this), 100 ether);
        MockERC20(address(eeth)).mint(address(this), 100 ether);

        // Approve router
        weth.approve(address(router), type(uint256).max);
        eeth.approve(address(router), type(uint256).max);
        weeth.approve(address(router), type(uint256).max);
        steth.approve(address(router), type(uint256).max);
        wsteth.approve(address(router), type(uint256).max);

        // Approve ARMs
        eeth.approve(address(etherfiARM), type(uint256).max);
        weth.approve(address(etherfiARM), type(uint256).max);
        steth.approve(address(lidoARM), type(uint256).max);
        weth.approve(address(lidoARM), type(uint256).max);
    }

    receive() external payable {}
}
