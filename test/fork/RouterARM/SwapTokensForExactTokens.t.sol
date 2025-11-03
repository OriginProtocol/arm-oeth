// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Fork_Shared_ARMRouter_Test} from "./Shared.sol";

contract Fork_Concrete_ARMRouter_SwapTokensForExactTokens_Test_ is Fork_Shared_ARMRouter_Test {
    function test_Swap_TokensForExactTokens_EETH_WETH() public {
        // Swap eeth to weth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        vm.startSnapshotGas("externalA");
        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_TokensForExactTokens_WEETH_WETH() public {
        // Swap weeth to weth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](3);
        path[0] = address(weeth);
        path[1] = address(eeth);
        path[2] = address(weth);

        vm.startSnapshotGas("externalB");
        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_TokensForExactTokens_WEETH_WSTETH() public {
        // Swap weeth to wsteth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](5);
        path[0] = address(weeth);
        path[1] = address(eeth);
        path[2] = address(weth);
        path[3] = address(steth);
        path[4] = address(wsteth);

        vm.startSnapshotGas("externalC");
        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactETHForTokens() public {
        // Swap eth to eeth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(eeth);

        vm.startSnapshotGas("externalD");
        router.swapExactETHForTokens{value: amountOut}(type(uint256).max, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactTokensForETH() public {
        // Swap eeth to eth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        vm.startSnapshotGas("externalE");
        router.swapExactTokensForETH(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }
}
