// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {Vm} from "forge-std/Vm.sol";

import {State} from "script/deploy/helpers/DeploymentTypes.sol";
import {Resolver} from "script/deploy/helpers/Resolver.sol";

abstract contract Base {
    Vm internal vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    Resolver internal resolver = Resolver(address(uint160(uint256(keccak256("Resolver")))));

    bool public log;
    bool public forcedLog = false;
    State public state;
    string public projectRoot = vm.projectRoot();

    mapping(uint256 chainId => string chainName) public chainNames;

    modifier pauseTracing() {
        vm.pauseTracing();
        _;
        vm.resumeTracing();
    }

    constructor() {
        chainNames[1] = "Ethereum Mainnet";
        chainNames[8453] = "Base Mainnet";
        chainNames[31337] = "Anvil";
    }
}
