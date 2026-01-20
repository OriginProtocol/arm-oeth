// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

enum State {
    DEFAULT,
    FORK_TEST,
    FORK_DEPLOYING,
    REAL_DEPLOYING
}

struct Execution {
    string name;
    uint256 timestamp;
}

struct Contract {
    address implementation;
    string name;
}

struct Root {
    Contract[] contracts;
    Execution[] executions;
}

struct GovAction {
    address target;
    uint256 value;
    string fullsig;
    bytes data;
}

struct GovProposal {
    string description;
    GovAction[] actions;
}
