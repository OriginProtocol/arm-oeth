// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

/// @title Unpause the Ethena ARM
/// @notice The Ethena ARM was left paused after the 031 multi-base upgrade and its ownership has since
///         moved from the 5/8 Guardian Safe to the mainnet Timelock. Unlike the earlier Ethena scripts
///         (which unpaused via a direct multisig prank), the ARM is now governance-owned, so unpausing
///         goes through a Timelock governance proposal — the same path used for LidoARM/EtherFiARM.
///         There is nothing to deploy; the script only builds the `unpause()` proposal.
/// @dev `make simulate` runs this through DeployManager against the latest mainnet state (where the ARM
///      is Timelock-owned) and logs the GOVERNANCE `propose()` calldata to submit. Fork/smoke tests
///      must therefore run against a post-transfer block (the default `latest`, per .env.example); at an
///      earlier block the ARM is not yet Timelock-owned and the proposal simulation reverts.
contract $035_UnpauseEthenaARMScript is AbstractDeployScript("035_UnpauseEthenaARMScript") {
    using GovHelper for GovProposal;

    bool public constant override skip = false;

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Unpause the Ethena ARM");

        // unpause() is onlyOwner; the owner is the Timelock, so it executes through governance.
        govProposal.action(resolver.resolve("ETHENA_ARM"), "unpause()", "");
    }
}
