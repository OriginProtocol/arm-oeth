// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry imports
import {console} from "forge-std/console.sol";

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment imports
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract EmptyScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "999_empty";
    bool public constant override proposalExecuted = false;

    function _execute() internal override {
        console.log("Empty deployment script - no actions taken");
    }
}
