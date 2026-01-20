// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";

// Deployment imports
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract UpgradeLidoARMSetBufferScript is AbstractDeployScript("009_UpgradeLidoARMSetBufferScript") {
    using GovHelper for GovProposal;

    bool public override skip = false;
    bool public constant override proposalExecuted = true;

    Proxy morphoMarketProxy;
    LidoARM lidoARMImpl;
    MorphoMarket morphoMarket;

    function _execute() internal override {
        // 1. Deploy new Lido implementation
        uint256 claimDelay = 10 minutes;
        lidoARMImpl = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay, 1e7, 1e18);
        _recordDeployment("LIDO_ARM_IMPL", address(lidoARMImpl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update Lido ARM to allow operator to setBuffer()");

        govProposal.action(
            resolver.implementations("LIDO_ARM"),
            "upgradeTo(address)",
            abi.encode(resolver.implementations("LIDO_ARM_IMPL"))
        );

        govProposal.action(resolver.implementations("LIDO_ARM"), "setCapManager(address)", abi.encode(address(0)));
    }
}
