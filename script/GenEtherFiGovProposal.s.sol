// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

// Foundry
import {console2} from "forge-std/console2.sol";

// Helpers
import {GovHelper} from "script/deploy/helpers/GovHelper.sol";
import {Root, State} from "script/deploy/helpers/DeploymentTypes.sol";

// Addresses
import {Mainnet} from "src/contracts/utils/Addresses.sol";

// The deploy script whose governance proposal we want to encode
import {$032_UpgradeEtherFiARMSwapFeeScript} from "script/deploy/mainnet/032_UpgradeEtherFiARMSwapFeeScript.s.sol";

/// @title GenEtherFiGovProposal
/// @notice Builds the EtherFi ARM (script 032) governance proposal in memory and prints the
///         `propose(...)` calldata WITHOUT simulating / executing it.
/// @dev One-off helper for the 032 deployment — safe to delete once the proposal is submitted.
/// @dev The deploy framework's fork path runs `GovHelper.simulate()`, which actually *executes*
///      the proposal on the fork. There, `upgradeToAndCall(impl, checkNoLegacyWithdrawQueue())`
///      reverts while the legacy withdraw queue is still non-empty. This helper only *builds*
///      the proposal — `getParams()` / `getProposeCalldata()` are pure, so it can never revert
///      on that check. The legacy queue must still be cleared before the real on-chain upgrade.
///
///      No RPC is needed: the proposal only references resolver addresses + constants.
///
///      Usage:
///        forge script script/GenEtherFiGovProposal.s.sol
contract GenEtherFiGovProposal is $032_UpgradeEtherFiARMSwapFeeScript {
    function run() external override {
        // 1. Bootstrap the deterministic Resolver singleton so resolver.resolve() works.
        vm.etch(address(resolver), vm.getDeployedCode("Resolver.sol:Resolver"));
        resolver.setState(State.FORK_DEPLOYING);

        // 2. Load the mainnet deployment history (the addresses the proposal references).
        Root memory root =
            abi.decode(vm.parseJson(vm.readFile(string.concat(projectRoot, "/build/deployments-1.json"))), (Root));
        for (uint256 i; i < root.contracts.length; ++i) {
            resolver.addContract(root.contracts[i].name, root.contracts[i].implementation);
        }

        // 3. Build the proposal in memory — no execution, so checkNoLegacyWithdrawQueue never runs.
        _buildGovernanceProposal();

        // 4. Print the full payload.
        (
            address[] memory targets,
            uint256[] memory values,
            string[] memory sigs,
            bytes[] memory data,
            bytes[] memory calldatas
        ) = GovHelper.getParams(govProposal);

        console2.log("Governor (GOVERNOR_SIX):", Mainnet.GOVERNOR_SIX);
        console2.log("Proposal id:", GovHelper.id(govProposal));
        console2.log("Description:", govProposal.description);

        for (uint256 i; i < targets.length; ++i) {
            console2.log("");
            console2.log("action", i);
            console2.log("  target:", targets[i]);
            console2.log("  value:", values[i]);
            console2.log("  sig:", sigs[i]);
            console2.log("  data (no selector):");
            console2.logBytes(data[i]);
            console2.log("  full calldata (selector + data):");
            console2.logBytes(calldatas[i]);
        }

        console2.log("");
        console2.log("=== propose() calldata to send to GOVERNOR_SIX ===");
        console2.logBytes(GovHelper.getProposeCalldata(govProposal));
    }
}
