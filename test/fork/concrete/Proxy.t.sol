// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {OEthARM} from "contracts/OethARM.sol";

// Test imports
import {Fork_Shared_Test_} from "../shared/Shared.sol";

// Utils
import {Mainnet} from "test/utils/Addresses.sol";

contract Fork_Concrete_OethARM_Proxy_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_UnauthorizedAccess() public {
        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.setOwner(deployer);

        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.initialize(address(this), address(this), "");

        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.upgradeTo(address(this));

        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.upgradeToAndCall(address(this), "");
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_Upgrade() public {
        address owner = Mainnet.TIMELOCK;

        // Deploy new implementation
        OEthARM newImplementation = new OEthARM();
        vm.prank(owner);
        proxy.upgradeTo(address(newImplementation));
        assertEq(proxy.implementation(), address(newImplementation));

        // Ensure ownership was preserved.
        assertEq(proxy.owner(), owner);
        assertEq(oethARM.owner(), owner);

        // Ensure the storage was preserved through the upgrade.
        assertEq(address(oethARM.token0()), Mainnet.OETH);
        assertEq(address(oethARM.token1()), Mainnet.WETH);
    }

    function test_UpgradeAndCall() public {
        address owner = Mainnet.TIMELOCK;

        // Deploy new implementation
        OEthARM newImplementation = new OEthARM();
        bytes memory data = abi.encodeWithSignature("setOperator(address)", address(0x123));

        vm.prank(owner);
        proxy.upgradeToAndCall(address(newImplementation), data);
        assertEq(proxy.implementation(), address(newImplementation));

        // Ensure ownership was preserved.
        assertEq(proxy.owner(), owner);
        assertEq(oethARM.owner(), owner);

        // Ensure the post upgrade code was run
        assertEq(oethARM.operator(), address(0x123));
    }
}
