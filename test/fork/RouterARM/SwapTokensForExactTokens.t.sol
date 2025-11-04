// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {ARMRouter} from "contracts/ARMRouter.sol";

// Tests
import {Fork_Shared_ARMRouter_Test} from "./Shared.sol";

contract Fork_Concrete_ARMRouter_SwapTokensForExactTokens_Test_ is Fork_Shared_ARMRouter_Test {
    ////////////////////////////////////////////////////
    ///                 Tests
    ////////////////////////////////////////////////////
    function test_Swap_TokensForExactTokens_EETH_WETH() public {
        // Swap eeth to weth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
    }

    function test_Swap_TokensForExactTokens_WEETH_WETH() public {
        // Swap weeth to weth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](3);
        path[0] = address(weeth);
        path[1] = address(eeth);
        path[2] = address(weth);

        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
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

        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
    }

    function test_Swap_ETHForExactTokens() public {
        // Swap eth to eeth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(eeth);

        router.swapETHForExactTokens{value: amountOut * 2}(amountOut, path, address(this), block.timestamp + 1);
    }

    function test_Swap_TokensForExactETH() public {
        // Swap eeth to eth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        router.swapTokensForExactETH(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
    }

    ////////////////////////////////////////////////////
    ///    Revert Tests - SwapTokensForExactTokens
    ////////////////////////////////////////////////////
    function test_Revert_When_SwapTokensForExactTokens_Because_ExcessiveInput() public {
        // Swap eeth to weth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        vm.expectRevert("ARMRouter: EXCESSIVE_INPUT");
        router.swapTokensForExactTokens(amountOut, 5 ether, path, address(this), block.timestamp + 1);
    }

    function test_Revert_When_SwapTokensForExactTokens_Because_Expired() public {
        // Swap eeth to weth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        vm.expectRevert("ARMRouter: EXPIRED");
        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp - 1);
    }

    function test_Revert_When_SwapTokensForExactTokens_Because_WrapFailed() public {
        router.registerConfig(
            address(eeth),
            address(weeth),
            ARMRouter.SwapType.WRAPPER,
            address(weeth),
            bytes4(0xffffffff),
            bytes4(0xffffffff)
        );

        // Swap eeth to weeth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weeth);

        vm.expectRevert("ARMRouter: WRAP_FAILED");
        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
    }

    function test_Revert_When_SwapTokensForExactTokens_Because_NotPathFound() public {
        // Swap eeth to weeth without registering config
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(steth);

        vm.expectRevert("ARMRouter: PATH_NOT_FOUND");
        router.swapTokensForExactTokens(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
    }

    ////////////////////////////////////////////////////
    ///    Revert Tests - SwapETHForExactTokens
    ////////////////////////////////////////////////////
    function test_Revert_When_SwapETHForExactTokens_Because_ExcessiveInput() public {
        // Swap eth to eeth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(eeth);

        vm.expectRevert("ARMRouter: EXCESSIVE_INPUT");
        router.swapETHForExactTokens{value: 5 ether}(amountOut, path, address(this), block.timestamp + 1);
    }

    function test_Revert_When_SwapETHForExactTokens_Because_InvalidPath() public {
        // Swap weth to eeth with invalid path
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        vm.expectRevert("ARMRouter: INVALID_PATH");
        router.swapETHForExactTokens{value: amountOut * 2}(amountOut, path, address(this), block.timestamp + 1);
    }

    ////////////////////////////////////////////////////
    ///    Revert Tests - SwapTokensForExactETH
    ////////////////////////////////////////////////////
    function test_Revert_When_SwapTokensForExactETH_Because_ExcessiveInput() public {
        // Swap eeth to eth
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weth);

        vm.expectRevert("ARMRouter: EXCESSIVE_INPUT");
        router.swapTokensForExactETH(amountOut, 5 ether, path, address(this), block.timestamp + 1);
    }

    function test_Revert_When_SwapTokensForExactETH_Because_InvalidPath() public {
        // Swap eeth to weth with invalid path
        uint256 amountOut = 10 ether;
        address[] memory path = new address[](2);
        path[0] = address(eeth);
        path[1] = address(weeth);

        vm.expectRevert("ARMRouter: INVALID_PATH");
        router.swapTokensForExactETH(amountOut, type(uint256).max, path, address(this), block.timestamp + 1);
    }
}
