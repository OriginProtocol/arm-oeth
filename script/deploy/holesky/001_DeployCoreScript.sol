// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {OethARM} from "contracts/OethARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Holesky} from "contracts/utils/Addresses.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract DeployCoreHoleskyScript is AbstractDeployScript {
    string public constant override DEPLOY_NAME = "001_CoreHolesky";
    bool public constant override proposalExecuted = false;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy proxy contracts
        Proxy proxy = new Proxy();
        _recordDeploy("OETH_ARM", address(proxy));

        // 2. Deploy implementation
        OethARM implementation = new OethARM(Holesky.OETH, Holesky.WETH, Holesky.OETH_VAULT);
        _recordDeploy("OETH_ARM_IMPL", address(implementation));

        // 3. Initialize proxy, set the owner and operator to the RELAYER and approve the OETH Vault to transfer OETH
        bytes memory data = abi.encodeWithSignature("initialize(address)", Holesky.RELAYER);
        proxy.initialize(address(implementation), Holesky.RELAYER, data);
    }
}
