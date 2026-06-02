// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

/// @notice Migrates the operator of LidoARM and EtherFiARM (both owned by the
/// mainnet Timelock) from the ARM Operations Defender relayer to the new Talos
/// KMS signer. setOperator is onlyOwner on OwnableOperable, so this routes
/// through a GovernorSix -> Timelock proposal.
contract $029_SetTalosKMSOperatorScript is AbstractDeployScript("029_SetTalosKMSOperatorScript") {
    using GovHelper for GovProposal;

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Migrate LidoARM and EtherFiARM operator to the new Talos KMS signer");

        govProposal.action(
            resolver.resolve("LIDO_ARM"), "setOperator(address)", abi.encode(Mainnet.TALOS_KMS_RELAYER)
        );

        govProposal.action(
            resolver.resolve("ETHER_FI_ARM"), "setOperator(address)", abi.encode(Mainnet.TALOS_KMS_RELAYER)
        );
    }
}
