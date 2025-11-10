// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_ARMRouter_Test} from "test/unit/Router/shared/Shared.sol";

import {WETH} from "@solmate/tokens/WETH.sol";
import {MockWrapper} from "test/unit/Router/shared/mocks/MockWrapper.sol";

abstract contract Unit_Concrete_ARMRouter_SwapTokensForExactTokens_Test is Unit_Shared_ARMRouter_Test {
    function test_Swap_TokensForExactTokens_ByPassRouter() public {
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        uint256 balanceBefore = weth.balanceOf(address(this));
        vm.startSnapshotGas("TokensForExactTokens: Bypass Router: EETH_WETH");
        etherfiARM.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
        assertEq(weth.balanceOf(address(this)), balanceBefore + amountOut);
    }

    function test_Swap_TokensForExactTokens_EETH_WETH() public {
        // Swap eeth to weth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        uint256 balanceBefore = weth.balanceOf(address(this));
        vm.startSnapshotGas("TokensForExactTokens: EETH_WETH");
        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
        assertEq(weth.balanceOf(address(this)), balanceBefore + amountOut);
    }

    function test_Swap_TokensForExactTokens_WETH_EETH() public {
        // Swap weth to eeth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(eeth);

        uint256 balanceBefore = eeth.balanceOf(address(this));
        vm.startSnapshotGas("TokensForExactTokens: WETH_EETH");
        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
        assertEq(eeth.balanceOf(address(this)), balanceBefore + amountOut);
    }

    function test_Swap_TokensForExactTokens_WEETH_WETH() public {
        uint256 amountOut = 10 ether;

        // Swap weeth to weth
        MockWrapper(address(weeth)).wrap(amountOut + 1 ether);
        address[] memory path = new address[](3);
        path[0] = address(weeth);
        path[1] = address(eeth);
        path[2] = address(weth);

        uint256 balanceBefore = weth.balanceOf(address(this));
        vm.startSnapshotGas("TokensForExactTokens: WEETH_WETH");
        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
        assertEq(weth.balanceOf(address(this)), balanceBefore + amountOut);
    }

    function test_Swap_TokensForExactTokens_WETH_WEETH() public {
        uint256 amountOut = 10 ether;

        // Swap weth to weeth
        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(eeth);
        path[2] = address(weeth);

        uint256 balanceBefore = weeth.balanceOf(address(this));
        vm.startSnapshotGas("TokensForExactTokens: WETH_WEETH");
        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
        assertEq(weeth.balanceOf(address(this)), balanceBefore + amountOut);
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

        uint256 balanceBefore = wsteth.balanceOf(address(this));
        vm.startSnapshotGas("TokensForExactTokens: WEETH_WSTETH");
        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
        assertEq(wsteth.balanceOf(address(this)), balanceBefore + amountOut);
    }

    function test_Swap_TokensForExactTokens_WSTETH_WEETH() public {
        uint256 amountOut = 10 ether;

        // Swap wsteth to weeth
        MockWrapper(address(wsteth)).wrap(amountOut + 1 ether);
        address[] memory path = new address[](5);
        path[0] = address(wsteth);
        path[1] = address(steth);
        path[2] = address(weth);
        path[3] = address(eeth);
        path[4] = address(weeth);

        uint256 balanceBefore = weeth.balanceOf(address(this));
        vm.startSnapshotGas("TokensForExactTokens: WSTETH_WEETH");
        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
        assertEq(weeth.balanceOf(address(this)), balanceBefore + amountOut);
    }

    function test_Swap_ETHForExactTokens() public {
        uint256 amountOut = 10 ether;

        // Swap eth to wsteth
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(eeth);

        deal(address(this), 20 ether);
        uint256 balanceBefore = eeth.balanceOf(address(this));
        vm.startSnapshotGas("ETHForExactTokens: EETH");
        router.swapETHForExactTokens{value: 20 ether}(amountOut, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
        assertEq(eeth.balanceOf(address(this)), balanceBefore + amountOut);
    }

    function test_Swap_TokensForExactETH() public {
        uint256 amountOut = 10 ether;

        // Swap eeth to eth
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        uint256 balanceBefore = address(this).balance;
        vm.startSnapshotGas("TokensForExactETH: EETH");
        router.swapTokensForExactETH(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
        assertEq(address(this).balance, balanceBefore + amountOut);
    }
}
