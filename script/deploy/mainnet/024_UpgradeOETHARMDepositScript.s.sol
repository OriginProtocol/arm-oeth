// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

// The original contract and governance imports are retained as comments with the implementation
// below. This script was superseded before execution and is permanently skipped. DeployManager must
// still deploy the script artifact to read skip(), so active OriginARM creation code would introduce
// an unresolved ARMAdapterLib link and prevent the deployment runner from loading this skip marker.
// import {OriginARM} from "contracts/OriginARM.sol";
// import {Mainnet} from "contracts/utils/Addresses.sol";
// import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

/// @dev Legacy deployment retained as an inert skip marker. It was superseded before execution.
contract $024_UpgradeOETHARMDepositScript is AbstractDeployScript("024_UpgradeOETHARMDepositScript") {
    bool public constant override skip = true;

    // The original deployment logic is commented out for the same linking reason documented above.
    // It remains here as historical context for why this deployment file exists.
    //
    // using GovHelper for GovProposal;
    //
    // function _execute() internal override {
    //     // 1. Deploy new OriginARM implementation
    //     uint256 claimDelay = 10 minutes;
    //     uint256 minSharesToRedeem = 1e7;
    //     int256 allocateThreshold = 1e18;
    //     OriginARM originARMImpl = new OriginARM(
    //         Mainnet.OETH,
    //         Mainnet.WETH,
    //         Mainnet.OETH_VAULT,
    //         claimDelay,
    //         minSharesToRedeem,
    //         allocateThreshold
    //     );
    //     _recordDeployment("OETH_ARM_IMPL", address(originARMImpl));
    // }
    //
    // function _buildGovernanceProposal() internal override {
    //     govProposal.setDescription("Upgrade OETH ARM to restrict deposits during insolvency");
    //
    //     govProposal.action(
    //         resolver.resolve("OETH_ARM"),
    //         "upgradeTo(address)",
    //         abi.encode(resolver.resolve("OETH_ARM_IMPL"))
    //     );
    // }
}
