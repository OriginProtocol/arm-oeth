// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {VmSafe} from "forge-std/Vm.sol";

// Test imports
import {Helpers} from "test/fork/utils/Helpers.sol";
import {MockCall} from "test/fork/utils/MockCall.sol";

abstract contract Modifiers is Helpers {
    /// @notice Impersonate Alice.
    modifier asAlice() {
        vm.startPrank(alice);
        _;
        vm.stopPrank();
    }

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
        vm.startPrank(lidoFixedPriceMulltiLpARM.owner());
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

    /// @notice Set the liquidity provider cap for a given provider on the LiquidityProviderController contract.
    modifier setLiquidityProviderCap(address provider, uint256 cap) {
        address[] memory providers = new address[](1);
        providers[0] = provider;

        liquidityProviderController.setLiquidityProviderCaps(providers, cap);
        _;
    }

    /// @notice Set the total assets cap on the LiquidityProviderController contract.
    modifier setTotalAssetsCap(uint256 cap) {
        liquidityProviderController.setTotalAssetsCap(cap);
        _;
    }

    modifier depositInLidoFixedPriceMultiLpARM(address user, uint256 amount) {
        // Todo: extend this logic to other modifier if needed
        (VmSafe.CallerMode mode, address _address, address _origin) = vm.readCallers();
        vm.stopPrank();

        // Check current balance
        uint256 balance = weth.balanceOf(user);

        // Deal amount as "extra" to user
        deal(address(weth), user, amount + balance);
        vm.startPrank(user);
        weth.approve(address(lidoFixedPriceMulltiLpARM), type(uint256).max);
        lidoFixedPriceMulltiLpARM.deposit(amount);
        vm.stopPrank();

        if (mode == VmSafe.CallerMode.Prank) {
            vm.prank(_address, _origin);
        } else if (mode == VmSafe.CallerMode.RecurrentPrank) {
            vm.startPrank(_address, _origin);
        }
        _;
    }

    /// @notice Request redeem from LidoFixedPriceMultiLpARM contract.
    modifier requestRedeemFromLidoFixedPriceMultiLpARM(address user, uint256 amount) {
        // Todo: extend this logic to other modifier if needed
        (VmSafe.CallerMode mode, address _address, address _origin) = vm.readCallers();
        vm.stopPrank();

        vm.startPrank(user);
        lidoFixedPriceMulltiLpARM.requestRedeem(amount);
        vm.stopPrank();

        if (mode == VmSafe.CallerMode.Prank) {
            vm.prank(_address, _origin);
        } else if (mode == VmSafe.CallerMode.RecurrentPrank) {
            vm.startPrank(_address, _origin);
        }
        _;
    }

    modifier claimRequestOnLidoFixedPriceMultiLpARM(address user, uint256 requestId) {
        // Todo: extend this logic to other modifier if needed
        (VmSafe.CallerMode mode, address _address, address _origin) = vm.readCallers();
        vm.stopPrank();

        vm.startPrank(user);
        lidoFixedPriceMulltiLpARM.claimRedeem(requestId);
        vm.stopPrank();

        if (mode == VmSafe.CallerMode.Prank) {
            vm.prank(_address, _origin);
        } else if (mode == VmSafe.CallerMode.RecurrentPrank) {
            vm.startPrank(_address, _origin);
        }
        _;
    }

    modifier skipTime(uint256 delay) {
        skip(delay);
        _;
    }
}
