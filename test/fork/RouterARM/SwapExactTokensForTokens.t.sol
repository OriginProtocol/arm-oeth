// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Fork_Shared_ARMRouter_Test} from "./Shared.sol";

import {ARMRouter} from "contracts/ARMRouter.sol";

contract Fork_Concrete_ARMRouter_SwapExactTokensForTokens_Test_ is Fork_Shared_ARMRouter_Test {
    function test_Swap_ExactTokensForTokens_EETH_WETH() public {
        // Swap eeth to weth
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        vm.startSnapshotGas("externalA");
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactTokensForTokens_WEETH_WETH() public {
        // Swap weeth to weth
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](3);
        path[0] = address(weeth);
        path[1] = address(eeth);
        path[2] = address(weth);

        vm.startSnapshotGas("externalB");
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactTokensForTokens_WEETH_WSTETH() public {
        // Swap weeth to wsteth
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](5);
        path[0] = address(weeth);
        path[1] = address(eeth);
        path[2] = address(weth);
        path[3] = address(steth);
        path[4] = address(wsteth);

        vm.startSnapshotGas("externalC");
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactETHForTokens() public {
        // Swap eth to eeth
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(eeth);

        vm.startSnapshotGas("externalD");
        router.swapExactETHForTokens{value: amountIn}(0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Swap_ExactTokensForETH() public {
        // Swap eeth to eth
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        vm.startSnapshotGas("externalE");
        router.swapExactTokensForETH(amountIn, 0, path, address(this), block.timestamp + 1);
        vm.stopSnapshotGas();
    }

    function test_Revert_Because_Insufficient_Output() public {
        // Swap eeth to weth with high min amount out
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        vm.expectRevert("ARMRouter: INSUFFICIENT_OUTPUT");
        router.swapExactTokensForTokens(amountIn, 12 ether, path, address(this), block.timestamp + 1);
    }

    function test_Revert_Because_Expired() public {
        // Swap eeth to weth with expired deadline
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        vm.expectRevert("ARMRouter: EXPIRED");
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp - 1);
    }

    function test_Revert_Because_InvalidePath_EthIn() public {
        // Swap weth to eeth with invalid path
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(weeth);
        path[1] = address(eeth);

        vm.expectRevert("ARMRouter: INVALID_PATH");
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
    }

    function test_Revert_Because_InvalidePath_EthOut() public {
        // Swap eeth to weth with invalid path
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weeth);

        vm.expectRevert("ARMRouter: INVALID_PATH");
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
    }

    function test_Revert_Because_Wrap_Failed() public {
        router.registerConfig(
            address(eeth),
            address(weeth),
            ARMRouter.SwapType.WRAPPER,
            address(weeth),
            bytes4(0xffffffff),
            bytes4(0xffffffff)
        );

        // Swap eeth to weeth with invalid wrap selector
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weeth);

        vm.expectRevert("ARMRouter: WRAP_UNWRAP_FAILED");
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
    }

    function test_Revert_Because_PathNotFound() public {
        // Swap eeth to weth with unregistered path
        uint256 amountIn = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(steth);

        vm.expectRevert("ARMRouter: PATH_NOT_FOUND");
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);
    }
}
