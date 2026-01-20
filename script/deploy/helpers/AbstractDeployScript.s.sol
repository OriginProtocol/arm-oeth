// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {Vm} from "forge-std/Vm.sol";

import {Base} from "script/deploy/Base.s.sol";
import {Logger} from "script/deploy/helpers/Logger.sol";
import {Resolver} from "script/deploy/helpers/Resolver.sol";
import {GovHelper} from "script/deploy/helpers/GovHelper.sol";
import {State, Contract, GovProposal} from "script/deploy/helpers/DeploymentTypes.sol";

abstract contract AbstractDeployScript is Base {
    using Logger for bool;

    string public name;
    address public deployer;
    Contract[] public contracts;
    GovProposal public govProposal;

    constructor(string memory _name) {
        name = _name;
        log = state != State.FORK_TEST || forcedLog;
    }

    function run() external virtual {
        // 1. Get state from Resolver (FORK_TEST, FORK_DEPLOYING, REAL_DEPLOYING)
        state = resolver.getState();

        // 2. Get deployer address from .env
        require(vm.envExists("DEPLOYER_ADDRESS"), "DEPLOYER_ADDRESS not set in .env");
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        log.logDeployer(deployer, state == State.FORK_TEST || state == State.FORK_DEPLOYING);

        // Start broadcast/prank depending on state
        if (state == State.REAL_DEPLOYING) vm.startBroadcast(deployer);
        if (state == State.FORK_TEST || state == State.FORK_DEPLOYING) vm.startPrank(deployer);

        // 3. Execute deployment
        log.section(string.concat("Executing: ", name));
        _execute();
        log.endSection();

        // 4. Stop broadcast
        if (state == State.REAL_DEPLOYING) vm.stopBroadcast();
        if (state == State.FORK_TEST || state == State.FORK_DEPLOYING) vm.stopPrank();

        // 5. Store deployed contracts in Resolver
        _storeDeployedContract();

        // 6. Build Governance proposals if any (out of scope for now)
        _buildGovernanceProposal();

        // 7. Handle Governance proposal, depending on state
        if (govProposal.actions.length == 0) {
            log.info("No governance proposal to handle");
            return;
        }
        if (govProposal.actions.length != 0) {
            if (state == State.REAL_DEPLOYING) GovHelper.logProposalData(log, govProposal);
            if (state == State.FORK_TEST || state == State.FORK_DEPLOYING) GovHelper.simulate(log, govProposal);
        }

        // 8. Run fork simulations if any (out of scope for now)
        if (state == State.FORK_TEST || state == State.FORK_DEPLOYING) _fork();
    }

    function _recordDeployment(string memory contractName, address implementation) internal virtual {
        contracts.push(Contract({implementation: implementation, name: contractName}));
        log.logContractDeployed(contractName, implementation);
    }

    function _storeDeployedContract() internal virtual {
        for (uint256 i = 0; i < contracts.length; i++) {
            resolver.addContract(contracts[i].name, contracts[i].implementation);
        }
        resolver.addExecution(name, block.timestamp);
    }

    function _fork() internal virtual {}
    function _execute() internal virtual;
    function _buildGovernanceProposal() internal virtual {}

    function skip() external view virtual returns (bool);
    function proposalExecuted() external view virtual returns (bool);
    function handleGovernanceProposal() external virtual {}
}
