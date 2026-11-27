// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {GovHelper, GovProposal} from "./GovHelper.sol";

/// @notice Append both actions to the same governance proposal, in execution order.
library EthenaAdapterRollback {
    using GovHelper for GovProposal;

    function addRollback(GovProposal storage proposal, address adapterProxy, address previousImplementation) internal {
        proposal.action(adapterProxy, "checkQueueEmpty()", bytes(""));
        proposal.action(adapterProxy, "upgradeTo(address)", abi.encode(previousImplementation));
    }
}
