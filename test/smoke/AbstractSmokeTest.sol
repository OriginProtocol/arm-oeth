// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

// Foundry imports
import {Test} from "forge-std/Test.sol";

import {Resolver} from "script/deploy/helpers/Resolver.sol";
import {DeployManager} from "script/deploy/DeployManager.s.sol";

import {EthenaARM} from "contracts/EthenaARM.sol";
import {EthenaAssetAdapter} from "contracts/adapters/EthenaAssetAdapter.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

/// @dev Read the common prefix of the deployed ARM's configuration tuple.
interface IEthenaSmokePrices {
    function baseAssetConfigs(address base) external view returns (uint128, uint128, uint128, uint128);
}

abstract contract AbstractSmokeTest is Test {
    uint256 internal constant FEE_SCALE = 10000;
    uint256 internal constant DELAY_REQUEST = 30 minutes;

    Resolver internal resolver = Resolver(address(uint160(uint256(keccak256("Resolver")))));

    DeployManager internal deployManager;

    /// @notice Using setUp here instead of a constructor because in case of failing test,
    ///         constructors logs are not printed, while setUp logs are printed.
    function setUp() public virtual {
        // Check if the MAINNET_URL is set.
        require(vm.envExists("MAINNET_URL"), "MAINNET_URL not set");

        // Create a fork.
        // If block number is provided in the environment variables, use it.
        // Otherwise, use latest block.
        if (vm.envExists("FORK_BLOCK_NUMBER_MAINNET")) {
            uint256 blockNumber = vm.envUint("FORK_BLOCK_NUMBER_MAINNET");
            vm.createSelectFork(vm.envString("MAINNET_URL"), blockNumber);
        } else {
            vm.createSelectFork(vm.envString("MAINNET_URL"));
        }

        _prepareEthenaUpgrade();
        deployManager = new DeployManager();

        // Run deployments
        deployManager.setUp();
        deployManager.run();
    }

    /// @dev Rehearse the operator steps required before proposal 044 on the shared mainnet fork.
    function _prepareEthenaUpgrade() private {
        EthenaAssetAdapter adapter = EthenaAssetAdapter(0xE620aFB67223AE03C260112aE21A717Af94C90f0);
        if (address(adapter).code.length == 0) return;
        EthenaARM arm = EthenaARM(payable(adapter.arm()));
        address operator = arm.operator();
        uint256 pendingShares;
        uint256 lastDeadline;
        for (uint256 i; i < adapter.MAX_UNSTAKERS(); ++i) {
            address slot = adapter.unstakers(i);
            uint256 shares = adapter.requestShares(slot);
            if (shares == 0) continue;
            pendingShares += shares;
            uint256 deadline = adapter.susde().cooldowns(slot).cooldownEnd;
            if (deadline > lastDeadline) lastDeadline = deadline;
        }
        if (pendingShares != 0) {
            if (adapter.susde().cooldownDuration() != 0 && lastDeadline > block.timestamp) vm.warp(lastDeadline);
            vm.prank(operator);
            arm.claimBaseAssetRedeem(Mainnet.SUSDE, pendingShares);
        }

        (uint128 buy, uint128 sell, uint128 buyLimit, uint128 sellLimit) =
            IEthenaSmokePrices(address(arm)).baseAssetConfigs(Mainnet.SUSDE);
        if (sell < 1e36) {
            vm.prank(operator);
            arm.setPrices(Mainnet.SUSDE, buy, 1e36, buyLimit, sellLimit);
        }
    }
}
