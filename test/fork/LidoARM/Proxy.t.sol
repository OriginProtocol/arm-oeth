// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {LidoARM} from "contracts/LidoARM.sol";

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
        vm.startPrank(address(0x123));
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoProxy.setOwner(deployer);

        vm.expectRevert("ARM: Only owner can call this function.");
        lidoProxy.initialize(address(this), address(this), "");

        vm.expectRevert("ARM: Only owner can call this function.");
        lidoProxy.upgradeTo(address(this));

        vm.expectRevert("ARM: Only owner can call this function.");
        lidoProxy.upgradeToAndCall(address(this), "");
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_Upgrade() public asLidoARMOwner {
        address owner = Mainnet.TIMELOCK;

        // Deploy new implementation
        LidoARM newImplementation = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.OETH_VAULT, 10 minutes, 0, 0);
        lidoProxy.upgradeTo(address(newImplementation));
        assertEq(lidoProxy.implementation(), address(newImplementation));

        // Ensure ownership was preserved.
        assertEq(lidoProxy.owner(), owner);
        assertEq(lidoARM.owner(), owner);

        // Ensure the storage was preserved through the upgrade.
        assertEq(address(lidoARM.token0()), Mainnet.WETH);
        assertEq(address(lidoARM.token1()), Mainnet.STETH);
    }

    function test_UpgradeAndCall() public asLidoARMOwner {
        address owner = Mainnet.TIMELOCK;

        // Deploy new implementation
        LidoARM newImplementation = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.OETH_VAULT, 10 minutes, 0, 0);
        bytes memory data = abi.encodeWithSignature("setOperator(address)", address(0x123));

        lidoProxy.upgradeToAndCall(address(newImplementation), data);
        assertEq(lidoProxy.implementation(), address(newImplementation));

        // Ensure ownership was preserved.
        assertEq(lidoProxy.owner(), owner);
        assertEq(lidoARM.owner(), owner);

        // Ensure the post upgrade code was run
        assertEq(lidoARM.operator(), address(0x123));
    }
}
