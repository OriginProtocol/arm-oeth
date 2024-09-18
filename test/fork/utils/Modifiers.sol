// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Helpers} from "test/fork/utils/Helpers.sol";
import {MockCall} from "test/fork/utils/MockCall.sol";

abstract contract Modifiers is Helpers {
    /// @notice Impersonate the owner of the contract.
    modifier asOwner() {
        vm.startPrank(oethARM.owner());
        _;
        vm.stopPrank();
    }

    /// @notice Impersonate the governor of the vault.
    modifier asGovernor() {
        vm.startPrank(vault.governor());
        _;
        vm.stopPrank();
    }

    /// @notice Impersonate the owner of LidoOwnerLpARM contract.
    modifier asLidoOwnerLpARMOwner() {
        vm.startPrank(lidoOwnerLpARM.owner());
        _;
        vm.stopPrank();
    }

    /// @notice Impersonate the operator of LidoOwnerLpARM contract.
    modifier asLidoOwnerLpARMOperator() {
        vm.startPrank(lidoOwnerLpARM.operator());
        _;
        vm.stopPrank();
    }

    /// @notice Impersonate the owner of LidoFixedPriceMultiLpARM contract.
    modifier asLidoFixedPriceMultiLpARMOwner() {
        vm.startPrank(lidoARM.owner());
        _;
        vm.stopPrank();
    }

    /// @notice Impersonate a random address
    modifier asRandomAddress() {
        vm.startPrank(vm.randomAddress());
        _;
        vm.stopPrank();
    }

    /// @notice Mock the call to the dripper's `collect` function, bypass it and return `true`.
    modifier mockCallDripperCollect() {
        MockCall.mockCallDripperCollect(vault.dripper());
        _;
    }

    /// @notice Set the liquidity provider cap for a given provider on the LidoFixedPriceMultiLpARM contract.
    modifier setLiquidityProviderCap(address provider, uint256 cap) {
        address[] memory providers = new address[](1);
        providers[0] = provider;

        liquidityProviderController.setLiquidityProviderCaps(providers, cap);
        _;
    }
}
