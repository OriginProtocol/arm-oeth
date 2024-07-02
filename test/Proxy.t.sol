// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/Test.sol";
import {AbstractForkTest} from "./AbstractForkTest.sol";

import {OEthARM} from "contracts/OethARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Addresses} from "contracts/utils/Addresses.sol";

contract ProxyTest is AbstractForkTest {
    address constant RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;

    Proxy proxy;
    OEthARM oethARM;

    address constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant oeth = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;

    address constant owner = Addresses.TIMELOCK;
    address constant operator = Addresses.STRATEGIST;

    function setUp() public {
        vm.label(weth, "WETH");
        vm.label(oeth, "OETH");

        proxy = Proxy(deployManager.getDeployment("OETH_ARM"));
        oethARM = OEthARM(deployManager.getDeployment("OETH_ARM"));
    }

    function test_upgrade() external {
        OEthARM newImplementation1 = new OEthARM();
        vm.prank(owner);
        proxy.upgradeTo(address(newImplementation1));
        assertEq(proxy.implementation(), address(newImplementation1));

        // Ensure ownership was preserved.
        assertEq(proxy.owner(), owner);
        assertEq(oethARM.owner(), owner);

        // Ensure the storage was preserved through the upgrade.
        assertEq(address(oethARM.token0()), oeth);
        assertEq(address(oethARM.token1()), weth);
    }

    function test_upgradeAndCall() external {
        OEthARM newImplementation2 = new OEthARM();
        bytes memory data = abi.encodeWithSignature("setOperator(address)", address(0x123));

        vm.prank(owner);
        proxy.upgradeToAndCall(address(newImplementation2), data);
        assertEq(proxy.implementation(), address(newImplementation2));

        // Ensure ownership was preserved.
        assertEq(proxy.owner(), owner);
        assertEq(oethARM.owner(), owner);

        // Ensure the post upgrade code was run
        assertEq(oethARM.operator(), address(0x123));
    }

    function test_setOwner() external {
        assertEq(proxy.owner(), owner);
        assertEq(oethARM.owner(), owner);

        // Update the owner.
        address newOwner = RANDOM_ADDRESS;
        vm.prank(owner);
        proxy.setOwner(newOwner);
        assertEq(proxy.owner(), newOwner);
        assertEq(oethARM.owner(), newOwner);

        // Old owner (this) should now be unauthorized.
        vm.expectRevert("ARM: Only owner can call this function.");
        oethARM.setOwner(address(this));
    }

    function test_unauthorizedAccess() external {
        // Proxy's restricted methods.
        vm.prank(RANDOM_ADDRESS);
        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.setOwner(RANDOM_ADDRESS);

        vm.prank(RANDOM_ADDRESS);
        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.initialize(address(this), address(this), "");

        vm.prank(RANDOM_ADDRESS);
        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.upgradeTo(address(this));

        vm.prank(RANDOM_ADDRESS);
        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.upgradeToAndCall(address(this), "");

        // Implementation's restricted methods.
        vm.prank(RANDOM_ADDRESS);
        vm.expectRevert("ARM: Only owner can call this function.");
        oethARM.setOwner(RANDOM_ADDRESS);
    }
}
