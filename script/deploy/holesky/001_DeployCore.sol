// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "./BaseHoleskyScript.sol";
import {Vm} from "forge-std/Vm.sol";

import {Holesky} from "contracts/utils/Addresses.sol";

import {OEthARM} from "contracts/OethARM.sol";
import {Proxy} from "contracts/Proxy.sol";

import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";

contract DeployCoreScript is BaseHoleskyScript {
    string public constant override DEPLOY_NAME = "001_DeployCoreScript";

    constructor() {}

    function _execute() internal override {
        console.log("Deploy:");
        console.log("------------");

        // 1. Deploy proxy contracts
        Proxy proxy = new Proxy();
        _recordDeploy("OETH_ARM", address(proxy));

        // 2. Deploy implementation
        OEthARM implementation = new OEthARM(Holesky.OETH, Holesky.WETH);
        _recordDeploy("OETH_ARM_IMPL", address(implementation));

        // 3. Initialize proxy, set the owner and the operator
        bytes memory data = abi.encodeWithSignature("setOperator(address)", Holesky.RELAYER);
        proxy.initialize(address(implementation), Holesky.RELAYER, data);
    }

    function _fork() internal override {}
}
