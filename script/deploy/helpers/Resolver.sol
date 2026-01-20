// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {State, Execution, Contract} from "script/deploy/helpers/DeploymentTypes.sol";

contract Resolver {
    State public currentState;
    Contract[] public contracts;
    Execution[] public executions;

    mapping(string => bool) public executionExists;
    mapping(string => address) public implementations;

    event ExecutionAdded(string name, uint256 timestamp);
    event ContractAdded(string name, address implementation);

    function addContract(string memory name, address implementation) external {
        contracts.push(Contract({name: name, implementation: implementation}));
        implementations[name] = implementation;
        emit ContractAdded(name, implementation);
    }

    function addExecution(string memory name, uint256 timestamp) external {
        executions.push(Execution({name: name, timestamp: timestamp}));
        executionExists[name] = true;
        emit ExecutionAdded(name, timestamp);
    }

    function getContracts() external view returns (Contract[] memory) {
        return contracts;
    }

    function getExecutions() external view returns (Execution[] memory) {
        return executions;
    }

    function setState(State newState) external {
        currentState = newState;
    }

    function getState() external view returns (State) {
        return currentState;
    }
}
