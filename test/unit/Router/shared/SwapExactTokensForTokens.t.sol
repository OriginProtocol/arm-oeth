// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_ARMRouter_Test} from "test/unit/Router/shared/Shared.sol";

import {WETH} from "@solmate/tokens/WETH.sol";
import {MockWrapper} from "test/unit/Router/shared/mocks/MockWrapper.sol";

abstract contract Unit_Concrete_ARMRouter_SwapExactTokensForTokens_Test is Unit_Shared_ARMRouter_Test {
    function test_Swap_ExactTokensForTokens_ByPassRouter() public {
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        vm.startSnapshotGas("ExactTokensForTokens: Bypass Router: EETH_WETH");
        etherfiARM.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactTokensForTokens_EETH_WETH() public {
        // Swap eeth to weth
        //uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        vm.startSnapshotGas("ExactTokensForTokens: EETH_WETH");
        router.swapExactTokensForTokens(10 ether, 0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactTokensForTokens_WETH_EETH() public {
        // Swap weth to eeth
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(eeth);

        vm.startSnapshotGas("ExactTokensForTokens: WETH_EETH");
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactTokensForTokens_WEETH_WETH() public {
        MockWrapper(address(weeth)).wrap(10 ether);
        // Swap weeth to weth
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](3);
        path[0] = address(weeth);
        path[1] = address(eeth);
        path[2] = address(weth);

        vm.startSnapshotGas("ExactTokensForTokens: WEETH_WETH");
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactTokensForTokens_WETH_WEETH() public {
        // Swap weth to weeth
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(eeth);
        path[2] = address(weeth);

        vm.startSnapshotGas("ExactTokensForTokens: WETH_WEETH");
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactTokensForTokens_WEETH_WSTETH() public {
        MockWrapper(address(weeth)).wrap(10 ether);
        // Swap weeth to wsteth
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](5);
        path[0] = address(weeth);
        path[1] = address(eeth);
        path[2] = address(weth);
        path[3] = address(steth);
        path[4] = address(wsteth);

        vm.startSnapshotGas("ExactTokensForTokens: WEETH_WSTETH");
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactTokensForTokens_WSTETH_WEETH() public {
        MockWrapper(address(wsteth)).wrap(10 ether);
        // Swap wsteth to weeth
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](5);
        path[0] = address(wsteth);
        path[1] = address(steth);
        path[2] = address(weth);
        path[3] = address(eeth);
        path[4] = address(weeth);

        vm.startSnapshotGas("ExactTokensForTokens: WSTETH_WEETH");
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactETHForTokens_EETH() public {
        // Swap eth to eeth
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(eeth);

        deal(address(this), amountIn);
        vm.startSnapshotGas("ExactETHForTokens: EETH");
        router.swapExactETHForTokens{value: amountIn}(0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactTokensForETH_EETH() public {
        // Swap eeth to eth
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        vm.startSnapshotGas("ExactTokensForETH: EETH");
        router.swapExactTokensForETH(amountIn, 0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }
}
