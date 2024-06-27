// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {IERC20} from "../src/contracts/Interfaces.sol";
import {OEthARM} from "../src/contracts/OEthARM.sol";
import {Proxy} from "../src/contracts/Proxy.sol";

// Tests for the Uniswap V2 Router compatible interface of OSwap.
contract UniswapV2Test is Test {
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 oeth = IERC20(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3);

    Proxy proxy;
    OEthARM oethARM;

    function setUp() public {
        OEthARM implementation = new OEthARM();
        proxy = new Proxy();
        proxy.initialize(address(implementation), address(this), "");

        oethARM = OEthARM(address(proxy));

        // Add liquidity to the test contract.
        _dealWETH(address(this), 120 ether);
        _dealOEth(address(this), 120 ether);

        // Add liquidity to the pool.
        _dealWETH(address(oethARM), 120 ether);
        _dealOEth(address(oethARM), 120 ether);

        weth.approve(address(oethARM), type(uint256).max);
        oeth.approve(address(oethARM), type(uint256).max);
        vm.label(address(weth), "WETH");
        vm.label(address(oeth), "stETH");
    }

    function _dealOEth(address to, uint256 amount) internal {
        vm.prank(0x8E02247D3eE0E6153495c971FFd45Aa131f4D7cB); // OETH whale
        oeth.transfer(to, amount);
    }

    function _dealWETH(address to, uint256 amount) internal {
        deal(address(weth), to, amount);
    }

    function test_swapExactOEthForWeth() external {
        address[] memory path = new address[](2);
        path[0] = address(oeth);
        path[1] = address(weth);
        uint256 balanceBefore = weth.balanceOf(address(this));

        uint256[] memory amounts = oethARM.swapExactTokensForTokens(100 ether, 99, path, address(this), block.timestamp);

        assertGt(amounts[0], 0, "amount[0] should not be zero");
        assertGt(amounts[1], 0, "amount[1] should not be zero");
        assertGe(weth.balanceOf(address(this)), balanceBefore + amounts[1], "received all output amount");
    }

    function test_swapStEthForExactWeth() external {
        address[] memory path = new address[](2);
        path[0] = address(oeth);
        path[1] = address(weth);
        uint256 balanceBefore = weth.balanceOf(address(this));

        uint256[] memory amounts =
            oethARM.swapTokensForExactTokens(100 ether, 101 ether, path, address(this), block.timestamp);

        assertGt(amounts[0], 0, "amount[0] should not be zero");
        assertGt(amounts[1], 0, "amount[1] should not be zero");
        assertGe(weth.balanceOf(address(this)), balanceBefore + amounts[1], "received all output amount");
    }

    function test_deadline() external {
        address[] memory path = new address[](2);
        vm.expectRevert("ARM: Deadline expired");
        oethARM.swapExactTokensForTokens(0, 0, path, address(this), block.timestamp - 1);
    }
}
