// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {OEthARM} from "contracts/OEthARM.sol";

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Utils
import {Mainnet} from "contracts/utils/Addresses.sol";

/// @notice The purpose of this contract is to test the `Proxy` contract.
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
    function test_Upgrade() public asOwner {
        address owner = Mainnet.TIMELOCK;

        // Deploy new implementation
        OEthARM newImplementation = new OEthARM(Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT);
        proxy.upgradeTo(address(newImplementation));
        assertEq(proxy.implementation(), address(newImplementation));

        // Ensure ownership was preserved.
        assertEq(proxy.owner(), owner);
        assertEq(oethARM.owner(), owner);

        // Ensure the storage was preserved through the upgrade.
        assertEq(address(oethARM.token0()), Mainnet.OETH);
        assertEq(address(oethARM.token1()), Mainnet.WETH);
    }

    function test_UpgradeAndCall() public asOwner {
        address owner = Mainnet.TIMELOCK;

        // Deploy new implementation
        OEthARM newImplementation = new OEthARM(Mainnet.OETH, Mainnet.WETH, Mainnet.OETH_VAULT);
        bytes memory data = abi.encodeWithSignature("setOperator(address)", address(0x123));

        proxy.upgradeToAndCall(address(newImplementation), data);
        assertEq(proxy.implementation(), address(newImplementation));

        // Ensure ownership was preserved.
        assertEq(proxy.owner(), owner);
        assertEq(oethARM.owner(), owner);

        // Ensure the post upgrade code was run
        assertEq(oethARM.operator(), address(0x123));
    }
}
