// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Vm} from "forge-std/Vm.sol";
import {Test, console2} from "forge-std/Test.sol";

import {OEthARM} from "contracts/OethARM.sol";
import {Proxy} from "contracts/Proxy.sol";

contract ProxyTest is Test {
    address constant RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;

    Proxy proxy;
    OEthARM oethARM;

    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address oeth = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;

    function setUp() public {
        // Deploy a OSwap contract implementation and a proxy.
        OEthARM implementation = new OEthARM();
        proxy = new Proxy();
        proxy.initialize(address(implementation), address(this), "");

        oethARM = OEthARM(address(proxy));
    }

    function test_upgrade() external {
        OEthARM newImplementation1 = new OEthARM();
        proxy.upgradeTo(address(newImplementation1));
        assertEq(proxy.implementation(), address(newImplementation1));

        // Ensure ownership was preserved.
        assertEq(proxy.owner(), address(this));
        assertEq(oethARM.owner(), address(this));

        // Ensure the storage was preserved through the upgrade.
        assertEq(address(oethARM.token0()), oeth);
        assertEq(address(oethARM.token1()), weth);
    }

    function test_upgradeAndCall() external {
        OEthARM newImplementation2 = new OEthARM();
        bytes memory data = abi.encodeWithSignature("setOperator(address)", address(this));
        proxy.upgradeToAndCall(address(newImplementation2), data);
        assertEq(proxy.implementation(), address(newImplementation2));

        // Ensure ownership was preserved.
        assertEq(proxy.owner(), address(this));
        assertEq(oethARM.owner(), address(this));

        // Ensure the post upgrade code was run
        assertEq(oethARM.operator(), address(this));
    }

    function test_setOwner() external {
        assertEq(proxy.owner(), address(this));
        assertEq(oethARM.owner(), address(this));

        // Update the owner.
        address newOwner = RANDOM_ADDRESS;
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
