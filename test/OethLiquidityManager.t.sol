// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console2} from "forge-std/Test.sol";
import {AbstractForkTest} from "./AbstractForkTest.sol";

import {IERC20, IOethARM, IOETHVault} from "contracts/Interfaces.sol";
import {OEthARM} from "contracts/OethARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Addresses} from "contracts/utils/Addresses.sol";

contract OethLiquidityManagerTest is AbstractForkTest {
    address constant RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    IERC20 constant oeth = IERC20(OETH);
    IERC20 constant weth = IERC20(WETH);

    IOETHVault constant vault = IOETHVault(0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab);

    Proxy proxy;
    OEthARM oethARM;

    address constant operator = Addresses.STRATEGIST;

    function setUp() public {
        vm.label(WETH, "WETH");
        vm.label(OETH, "OETH");

        proxy = Proxy(deployManager.getDeployment("OETH_ARM"));
        oethARM = OEthARM(deployManager.getDeployment("OETH_ARM"));
    }

    function test_withdrawal() external {
        uint256 amount = 1 ether;
        _dealOEth(address(proxy), 10 ether);
        // put some WETH in the vault
        _dealWEth(address(vault), 10 ether);

        vm.startPrank(operator);
        (uint256 requestId, uint256 queued) = oethARM.requestWithdrawal(1 ether);

        // Snapshot WETH balance
        uint256 startBalance = weth.balanceOf(address(oethARM));

        vault.addWithdrawalQueueLiquidity();

        // Claim the ETH.
        oethARM.claimWithdrawal(requestId);

        // Ensure the balance increased.
        assertGt(weth.balanceOf(address(oethARM)), startBalance, "Withdrawal did not increase WETH balance");

        vm.stopPrank();
    }

    /*
     * Admin tests.
     *
     */
    function test_unauthorizedAccess() external {
        vm.startPrank(RANDOM_ADDRESS);

        vm.expectRevert("ARM: Only operator or owner can call this function.");
        oethARM.requestWithdrawal(1 ether);

        vm.expectRevert("ARM: Only operator or owner can call this function.");
        oethARM.claimWithdrawal(1);

        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = 10;
        requestIds[1] = 22;

        vm.expectRevert("ARM: Only operator or owner can call this function.");
        oethARM.claimWithdrawals(requestIds);
    }

    function _dealOEth(address to, uint256 amount) internal {
        vm.prank(0x8E02247D3eE0E6153495c971FFd45Aa131f4D7cB); // OETH whale
        oeth.transfer(to, amount);
    }

    function _dealWEth(address to, uint256 amount) internal {
        vm.prank(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E); // WETH whale
        weth.transfer(to, amount);
    }
}
