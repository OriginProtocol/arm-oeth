// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {Mainnet} from "contracts/utils/Addresses.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

/// @notice Migrates the operator of EthenaARM from the ARM Operations Defender
/// relayer to the new Talos KMS signer. Unlike LidoARM/EtherFiARM (owned by the
/// mainnet Timelock and migrated via a governance proposal in 029), EthenaARM is
/// owned by the 5/8 Guardian Safe (GOV_MULTISIG) directly, so setOperator
/// (onlyOwner on OwnableOperable) is executed by that Safe. We simulate it with a
/// prank in fork; on real deployment the multisig executes the call.
contract $030_SetEthenaTalosKMSOperatorScript is AbstractDeployScript("030_SetEthenaTalosKMSOperatorScript") {
    function _fork() internal override {
        OwnableOperable ethenaARM = OwnableOperable(resolver.resolve("ETHENA_ARM"));

        if (ethenaARM.operator() != Mainnet.TALOS_RELAYER) {
            vm.startPrank(ethenaARM.owner());
            ethenaARM.setOperator(Mainnet.TALOS_RELAYER);
            vm.stopPrank();
        }
    }
}
