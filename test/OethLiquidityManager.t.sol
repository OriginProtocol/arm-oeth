// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// import {Test, console2} from "forge-std/Test.sol";

import {IERC20, IOethARM} from "../src/contracts/Interfaces.sol";
import {OEthARM} from "../src/contracts/OEthARM.sol";
import {Proxy} from "../src/contracts/Proxy.sol";

// contract OethLiquidityManagerTest is Test {
//     address constant RANDOM_ADDRESS =
//         0xfEEDBeef00000000000000000000000000000000;

//     address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
//     address constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
//     IERC20 constant oeth = IERC20(OETH);
//     IERC20 constant weth = IERC20(WETH);

//     IOETHVault constant vault =
//         IOETHVault(0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab);

//     Proxy proxy;
//     OEthARM oethARM;

//     function setUp() public {
//         vm.label(WETH, "WETH");
//         vm.label(OETH, "OETH");

//         OEthARM implementation = new OEthARM(oeth, weth);
//         proxy = new Proxy();
//         proxy.initialize(address(implementation), address(this), "");
//         oethARM = OEthARM(proxy);

//         oethARM.setOperator(address(this));
//     }

//     function test_withdrawal() external {
//         amount = 1 ether;
//         _dealOEth(address(proxy), 10 ether);

//         uint256 requestId = oethARM.requestWithdrawal(1 ether);

//         // Snapshot ETH balance
//         uint256 startBalance = address(oethARM).balance;

//         // Claim the ETH.
//         uint256[] memory requestIds = new uint256[](2);
//         requestIds[0] = requestId1;
//         requestIds[1] = requestId2;
//         oethARM.claimWithdrawal(requestId);

//         // Ensure the balance increased.
//         assertGt(
//             address(oethARM).balance,
//             startBalance,
//             "Withdrawal did not increase balance"
//         );
//     }

//     /*
//      * Admin tests.
//      *
//      */
//     function test_unauthorizedAccess() external {
//         vm.startPrank(RANDOM_ADDRESS);
//         uint256[] memory array = new uint256[](1);

//         vm.expectRevert("ARM: Only operator or owner can call this function.");
//         oethARM.requestWithdrawal(array);

//         vm.expectRevert("ARM: Only operator or owner can call this function.");
//         oethARM.claimWithdrawal(array);
//     }

//     function _dealOEth(address to, uint256 amount) internal {
//         vm.prank(0x3A341259100Fee4a5f610655104Eb28295e62e0F); // OETH whale
//         oeth.transfer(to, amount);
//     }

//     function _dealWEth(address to, uint256 amount) internal {
//         vm.prank(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E); // WETH whale
//         weth.transfer(to, amount);
//     }
// }
