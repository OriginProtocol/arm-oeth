// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {VmSafe} from "forge-std/Vm.sol";

// Test imports
import {Helpers} from "test/fork/utils/Helpers.sol";
import {MockCall} from "test/fork/utils/MockCall.sol";
import {MockLidoWithdraw} from "test/fork/utils/MockCall.sol";
import {ETHSender} from "test/fork/utils/MockCall.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";

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

    /// @notice Impersonate the operator of LidoOwnerLpARM contract.
    modifier asLidoFixedPriceMulltiLpARMOperator() {
        vm.startPrank(lidoARM.operator());
        _;
        vm.stopPrank();
    }

    /// @notice Impersonate the owner of LidoARM contract.
    modifier asLidoARMOwner() {
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

    /// @notice Deposit WETH into the LidoARM contract.
    modifier depositInLidoARM(address user, uint256 amount) {
        // Todo: extend this logic to other modifier if needed
        (VmSafe.CallerMode mode, address _address, address _origin) = vm.readCallers();
        vm.stopPrank();

        // Check current balance
        uint256 balance = weth.balanceOf(user);

        // Deal amount as "extra" to user
        deal(address(weth), user, amount + balance);
        vm.startPrank(user);
        weth.approve(address(lidoARM), type(uint256).max);
        lidoARM.deposit(amount);
        vm.stopPrank();

        if (mode == VmSafe.CallerMode.Prank) {
            vm.prank(_address, _origin);
        } else if (mode == VmSafe.CallerMode.RecurrentPrank) {
            vm.startPrank(_address, _origin);
        }
        _;
    }

    /// @notice Request redeem from LidoARM contract.
    modifier requestRedeemFromLidoARM(address user, uint256 amount) {
        // Todo: extend this logic to other modifier if needed
        (VmSafe.CallerMode mode, address _address, address _origin) = vm.readCallers();
        vm.stopPrank();

        vm.startPrank(user);
        lidoARM.requestRedeem(amount);
        vm.stopPrank();

        if (mode == VmSafe.CallerMode.Prank) {
            vm.prank(_address, _origin);
        } else if (mode == VmSafe.CallerMode.RecurrentPrank) {
            vm.startPrank(_address, _origin);
        }
        _;
    }

    /// @notice Claim redeem from LidoARM contract.
    modifier claimRequestOnLidoARM(address user, uint256 requestId) {
        // Todo: extend this logic to other modifier if needed
        (VmSafe.CallerMode mode, address _address, address _origin) = vm.readCallers();
        vm.stopPrank();

        vm.startPrank(user);
        lidoARM.claimRedeem(requestId);
        vm.stopPrank();

        if (mode == VmSafe.CallerMode.Prank) {
            vm.prank(_address, _origin);
        } else if (mode == VmSafe.CallerMode.RecurrentPrank) {
            vm.startPrank(_address, _origin);
        }
        _;
    }

    /// @notice Simulate asset gain or loss in LidoARM contract.
    modifier simulateAssetGainInLidoARM(uint256 assetGain, address token, bool gain) {
        // Todo: extend this logic to other modifier if needed
        (VmSafe.CallerMode mode, address _address, address _origin) = vm.readCallers();
        vm.stopPrank();

        if (gain) {
            deal(token, address(lidoARM), IERC20(token).balanceOf(address(lidoARM)) + uint256(assetGain));
        } else {
            deal(token, address(lidoARM), IERC20(token).balanceOf(address(lidoARM)) - uint256(assetGain));
        }

        if (mode == VmSafe.CallerMode.Prank) {
            vm.prank(_address, _origin);
        } else if (mode == VmSafe.CallerMode.RecurrentPrank) {
            vm.startPrank(_address, _origin);
        }
        _;
    }

    /// @notice Collect fees on LidoARM contract.
    modifier collectFeesOnLidoARM() {
        lidoARM.collectFees();
        _;
    }

    /// @notice Approve stETH on LidoARM contract.
    modifier approveStETHOnLidoARM() {
        // Todo: extend this logic to other modifier if needed
        (VmSafe.CallerMode mode, address _address, address _origin) = vm.readCallers();
        vm.stopPrank();

        vm.prank(lidoARM.owner());
        lidoARM.approveStETH();

        if (mode == VmSafe.CallerMode.Prank) {
            vm.prank(_address, _origin);
        } else if (mode == VmSafe.CallerMode.RecurrentPrank) {
            vm.startPrank(_address, _origin);
        }
        _;
    }

    /// @notice Request stETH withdrawal for ETH on LidoARM contract.
    modifier requestStETHWithdrawalForETHOnLidoARM(uint256[] memory amounts) {
        // Todo: extend this logic to other modifier if needed
        (VmSafe.CallerMode mode, address _address, address _origin) = vm.readCallers();
        vm.stopPrank();

        vm.prank(lidoARM.owner());
        lidoARM.requestStETHWithdrawalForETH(amounts);

        if (mode == VmSafe.CallerMode.Prank) {
            vm.prank(_address, _origin);
        } else if (mode == VmSafe.CallerMode.RecurrentPrank) {
            vm.startPrank(_address, _origin);
        }
        _;
    }

    /// @notice mock call for `findCheckpointHints`on lido withdraw contracts.
    modifier mockCallLidoFindCheckpointHints() {
        // Todo: extend this logic to other modifier if needed
        (VmSafe.CallerMode mode, address _address, address _origin) = vm.readCallers();
        vm.stopPrank();

        MockCall.mockCallLidoFindCheckpointHints();

        if (mode == VmSafe.CallerMode.Prank) {
            vm.prank(_address, _origin);
        } else if (mode == VmSafe.CallerMode.RecurrentPrank) {
            vm.startPrank(_address, _origin);
        }
        _;
    }

    /// @notice mock call for `claimWithdrawals` on lido withdraw contracts.
    /// @dev this will send eth directly to the lidoARM contract.
    modifier mockFunctionClaimWithdrawOnLidoARM(uint256 amount) {
        // Todo: extend this logic to other modifier if needed
        (VmSafe.CallerMode mode, address _address, address _origin) = vm.readCallers();
        vm.stopPrank();

        // Deploy fake lido withdraw contract
        MockLidoWithdraw mocklidoWithdraw = new MockLidoWithdraw(address(lidoARM));
        // Give ETH to the ETH Sender contract
        vm.deal(address(mocklidoWithdraw.ethSender()), amount);
        // Mock all the call to the fake lido withdraw contract
        MockCall.mockCallLidoClaimWithdrawals(address(mocklidoWithdraw));

        if (mode == VmSafe.CallerMode.Prank) {
            vm.prank(_address, _origin);
        } else if (mode == VmSafe.CallerMode.RecurrentPrank) {
            vm.startPrank(_address, _origin);
        }
        _;
    }

    /// @notice Skip time by a given delay.
    modifier skipTime(uint256 delay) {
        skip(delay);
        _;
    }
}
