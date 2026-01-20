// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

// Foundry
import {Vm} from "forge-std/Vm.sol";

// Helpers
import {Logger} from "script/deploy/helpers/Logger.sol";
import {GovAction, GovProposal} from "script/deploy/helpers/DeploymentTypes.sol";

// Utils
import {Mainnet} from "src/contracts/utils/Addresses.sol";

library GovHelper {
    using Logger for bool;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function id(GovProposal memory prop) internal pure returns (uint256 proposalId) {
        bytes32 descriptionHash = keccak256(bytes(prop.description));
        (address[] memory targets, uint256[] memory values,,, bytes[] memory calldatas) = getParams(prop);

        proposalId = uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    function getParams(GovProposal memory prop)
        internal
        pure
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory sigs,
            bytes[] memory data,
            bytes[] memory calldatas
        )
    {
        uint256 actionLen = prop.actions.length;
        targets = new address[](actionLen);
        values = new uint256[](actionLen);

        sigs = new string[](actionLen);
        data = new bytes[](actionLen);

        for (uint256 i = 0; i < actionLen; ++i) {
            targets[i] = prop.actions[i].target;
            values[i] = prop.actions[i].value;
            sigs[i] = prop.actions[i].fullsig;
            data[i] = prop.actions[i].data;
        }

        calldatas = _encodeCalldata(sigs, data);
    }

    function _encodeCalldata(string[] memory signatures, bytes[] memory calldatas)
        private
        pure
        returns (bytes[] memory)
    {
        bytes[] memory fullcalldatas = new bytes[](calldatas.length);

        for (uint256 i = 0; i < signatures.length; ++i) {
            fullcalldatas[i] = bytes(signatures[i]).length == 0
                ? calldatas[i]
                : abi.encodePacked(bytes4(keccak256(bytes(signatures[i]))), calldatas[i]);
        }

        return fullcalldatas;
    }

    function setDescription(GovProposal storage prop, string memory description) internal {
        prop.description = description;
    }

    function action(GovProposal storage prop, address target, string memory fullsig, bytes memory data) internal {
        prop.actions.push(GovAction({target: target, fullsig: fullsig, data: data, value: 0}));
    }

    function getProposeCalldata(GovProposal memory prop) internal pure returns (bytes memory proposeCalldata) {
        (address[] memory targets, uint256[] memory values, string[] memory sigs, bytes[] memory data,) =
            getParams(prop);

        proposeCalldata = abi.encodeWithSignature(
            "propose(address[],uint256[],string[],bytes[],string)", targets, values, sigs, data, prop.description
        );
    }

    function logProposalData(bool log, GovProposal memory prop) internal view {
        IGovernance governance = IGovernance(Mainnet.GOVERNOR_SIX);
        require(governance.proposalSnapshot(id(prop)) == 0, "Proposal already exists");

        log.logGovProposalHeader();
        log.logCalldata(address(governance), getProposeCalldata(prop));
    }

    function simulate(bool log, GovProposal memory prop) internal {
        address govMultisig = Mainnet.GOV_MULTISIG;
        vm.label(govMultisig, "Gov Multisig");

        IGovernance governance = IGovernance(Mainnet.GOVERNOR_SIX);
        vm.label(address(governance), "Governance");

        uint256 proposalId = id(prop);

        uint256 snapshot = governance.proposalSnapshot(proposalId);
        require(snapshot == 0, "Proposal already exists");

        if (snapshot == 0) {
            bytes memory proposeData = getProposeCalldata(prop);

            log.logGovProposalHeader();
            log.logCalldata(address(governance), proposeData);

            // Proposal doesn't exists, create it
            log.info("Simulation of the governance proposal:");
            log.info("Creating proposal on fork...");
            vm.prank(govMultisig);
            (bool success,) = address(governance).call(proposeData);
            if (!success) {
                revert("Fail to create proposal");
            }
            log.success("Proposal created");
        }

        IGovernance.ProposalState state = governance.state(proposalId);

        if (state == IGovernance.ProposalState.Executed) {
            // Skipping executed proposal
            log.success("Proposal already executed");
            return;
        }

        if (state == IGovernance.ProposalState.Pending) {
            log.info("Waiting for voting period...");
            // Wait for voting to start
            vm.roll(block.number + 7300);
            vm.warp(block.timestamp + 1 minutes);

            state = governance.state(proposalId);
        }

        if (state == IGovernance.ProposalState.Active) {
            log.info("Voting on proposal...");
            // Vote on proposal
            vm.prank(govMultisig);
            governance.castVote(proposalId, 1);
            // Wait for voting to end
            vm.roll(governance.proposalDeadline(proposalId) + 20);
            vm.warp(block.timestamp + 2 days);
            log.success("Vote cast");

            state = governance.state(proposalId);
        }

        if (state == IGovernance.ProposalState.Succeeded) {
            log.info("Queuing proposal...");
            // Queue proposal
            vm.prank(govMultisig);
            governance.queue(proposalId);
            log.success("Proposal queued");

            state = governance.state(proposalId);
        }

        if (state == IGovernance.ProposalState.Queued) {
            log.info("Executing proposal...");
            // Wait for timelock
            uint256 propEta = governance.proposalEta(proposalId);
            vm.roll(block.number + 10);
            vm.warp(propEta + 20);

            vm.prank(govMultisig);
            governance.execute(proposalId);
            log.success("Proposal executed");

            state = governance.state(proposalId);
        }

        if (state != IGovernance.ProposalState.Executed) {
            log.error("Unexpected proposal state");
            revert("Unexpected proposal state");
        }
    }

    function _proposalStateToString(IGovernance.ProposalState state) private pure returns (string memory) {
        if (state == IGovernance.ProposalState.Pending) return "Pending";
        if (state == IGovernance.ProposalState.Active) return "Active";
        if (state == IGovernance.ProposalState.Canceled) return "Canceled";
        if (state == IGovernance.ProposalState.Defeated) return "Defeated";
        if (state == IGovernance.ProposalState.Succeeded) return "Succeeded";
        if (state == IGovernance.ProposalState.Queued) return "Queued";
        if (state == IGovernance.ProposalState.Expired) return "Expired";
        if (state == IGovernance.ProposalState.Executed) return "Executed";
        return "Unknown";
    }
}

interface IGovernance {
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    function state(uint256 proposalId) external view returns (ProposalState);

    function proposalSnapshot(uint256 proposalId) external view returns (uint256);

    function proposalDeadline(uint256 proposalId) external view returns (uint256);

    function proposalEta(uint256 proposalId) external view returns (uint256);

    function votingDelay() external view returns (uint256);

    function castVote(uint256 proposalId, uint8 support) external returns (uint256 balance);

    function queue(uint256 proposalId) external;

    function execute(uint256 proposalId) external;
}
