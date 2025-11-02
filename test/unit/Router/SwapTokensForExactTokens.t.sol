// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_ARMRouter_Test} from "test/unit/Router/shared/Shared.sol";

import {WETH} from "@solmate/tokens/WETH.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockWrapper} from "test/unit/Router/shared/mocks/MockWrapper.sol";

contract Unit_Concrete_ARMRouter_SwapTokensForExactTokens_Test is Unit_Shared_ARMRouter_Test {
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

    function test_Swap_TokensForExactTokens_EETH_WETH() public {
        // Swap eeth to weth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
    }

    function test_Swap_TokensForExactTokens_WEETH_WETH() public {
        uint256 amountOut = 10 ether;

        // Swap weeth to weth
        MockWrapper(address(weeth)).wrap(amountOut + 1 ether);
        address[] memory path = new address[](3);
        path[0] = address(weeth);
        path[1] = address(eeth);
        path[2] = address(weth);

        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
    }

    function test_Swap_TokensForExactTokens_WEETH_WSTETH() public {
        uint256 amountOut = 10 ether;

        // Swap weeth to wsteth
        MockWrapper(address(weeth)).wrap(amountOut + 1 ether);
        address[] memory path = new address[](5);
        path[0] = address(weeth);
        path[1] = address(eeth);
        path[2] = address(weth);
        path[3] = address(steth);
        path[4] = address(wsteth);

        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
    }
}
