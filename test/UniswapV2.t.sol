// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// import {Test, console2} from "forge-std/Test.sol";

import {IERC20} from "../src/contracts/Interfaces.sol";
import {OEthARM} from "../src/contracts/OEthARM.sol";
import {Proxy} from "../src/contracts/Proxy.sol";

// // Tests for the Uniswap V2 Router compatible interface of OSwap.
// contract UniswapV2Test is Test {
//     IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
//     IERC20 steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

//     Proxy proxy;
//     OEthARM oethARM;

//     function setUp() public {
//         OEthARM implementation = new OEthARM();
//         proxy = new Proxy();
//         proxy.initialize(address(implementation), address(this), "");

//         oethARM = OEthARM(payable(proxy));

//         // Add liquidity to the test contract.
//         _dealWETH(address(this), 1000 ether);
//         _dealStETH(address(this), 1000 ether);

//         // Add liquidity to the pool.
//         _dealWETH(address(oswap), 1000 ether);
//         _dealStETH(address(oswap), 1000 ether);

//         // Set prices.
//         oswap.setPrices(997 * 1e33, 998 * 1e33);

//         weth.approve(address(oswap), type(uint256).max);
//         steth.approve(address(oswap), type(uint256).max);
//         vm.label(address(weth), "WETH");
//         vm.label(address(steth), "stETH");
//     }

//     function _dealStETH(address to, uint256 amount) internal {
//         vm.prank(0xEB9c1CE881F0bDB25EAc4D74FccbAcF4Dd81020a);
//         steth.transfer(to, amount);
//     }

//     function _dealWETH(address to, uint256 amount) internal {
//         deal(address(weth), to, amount);
//     }

//     function test_swapExactStEthForWeth() external {
//         address[] memory path = new address[](2);
//         path[0] = address(steth);
//         path[1] = address(weth);
//         uint256 balanceBefore = weth.balanceOf(address(this));

//         uint256[] memory amounts = oswap.swapExactTokensForTokens(100 ether, 99, path, address(this), block.timestamp);

//         assertGt(amounts[0], 0, "amount[0] should not be zero");
//         assertGt(amounts[1], 0, "amount[1] should not be zero");
//         assertGe(weth.balanceOf(address(this)), balanceBefore + amounts[1], "received all output amount");
//     }

//     function test_swapExactWethFoStEth() external {
//         address[] memory path = new address[](2);
//         path[0] = address(weth);
//         path[1] = address(steth);
//         uint256 balanceBefore = steth.balanceOf(address(this));

//         uint256[] memory amounts = oswap.swapExactTokensForTokens(100 ether, 99, path, address(this), block.timestamp);

//         assertGt(amounts[0], 0, "amount[0] should not be zero");
//         assertGt(amounts[1], 0, "amount[1] should not be zero");
//         assertGe(steth.balanceOf(address(this)), balanceBefore + amounts[1], "received all output amount");
//     }

//     function test_swapWethForExactStEth() external {
//         address[] memory path = new address[](2);
//         path[0] = address(weth);
//         path[1] = address(steth);
//         uint256 balanceBefore = steth.balanceOf(address(this));

//         uint256[] memory amounts =
//             oswap.swapTokensForExactTokens(100 ether, 101 ether, path, address(this), block.timestamp);

//         assertGt(amounts[0], 0, "amount[0] should not be zero");
//         assertGt(amounts[1], 0, "amount[1] should not be zero");
//         assertGe(steth.balanceOf(address(this)), balanceBefore + amounts[1], "received all output amount");
//     }

//     function test_swapStEthForExactWeth() external {
//         address[] memory path = new address[](2);
//         path[0] = address(steth);
//         path[1] = address(weth);
//         uint256 balanceBefore = weth.balanceOf(address(this));

//         uint256[] memory amounts =
//             oswap.swapTokensForExactTokens(100 ether, 101 ether, path, address(this), block.timestamp);

//         assertGt(amounts[0], 0, "amount[0] should not be zero");
//         assertGt(amounts[1], 0, "amount[1] should not be zero");
//         assertGe(weth.balanceOf(address(this)), balanceBefore + amounts[1], "received all output amount");
//     }

//     function test_deadline() external {
//         address[] memory path = new address[](2);
//         vm.expectRevert("OSwap: Deadline expired");
//         oswap.swapExactTokensForTokens(0, 0, path, address(this), block.timestamp - 1);
//     }
// }
