// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {CapManager} from "contracts/CapManager.sol";
import {ZapperLidoARM} from "contracts/ZapperLidoARM.sol";

// Deployment
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $017_UpgradeLidoARMScript is AbstractDeployScript("017_UpgradeLidoARMScript") {
    using GovHelper for GovProposal;

    bool public override proposalExecuted = false;

    Proxy lidoARMProxy;
    Proxy capManProxy;
    LidoARM lidoARMImpl;
    LidoARM lidoARM;
    CapManager capManager;
    ZapperLidoARM zapper;

    function _execute() internal override {
        // 1. Get the proxy address used for Lido ARM
        lidoARMProxy = Proxy(payable(Mainnet.LIDO_ARM));

        // 2. Deploy proxy for the CapManager
        capManProxy = new Proxy();
        _recordDeployment("LIDO_ARM_CAP_MAN", address(capManProxy));

        // 3. Deploy CapManager implementation
        CapManager capManagerImpl = new CapManager(address(lidoARMProxy));
        _recordDeployment("LIDO_ARM_CAP_IMPL", address(capManagerImpl));

        // 4. Initialize Proxy with CapManager implementation and set the owner to the deployer for now
        bytes memory data = abi.encodeWithSignature("initialize(address)", Mainnet.ARM_RELAYER);
        capManProxy.initialize(address(capManagerImpl), deployer, data);
        capManager = CapManager(address(capManProxy));

        // 5. Set total assets cap
        capManager.setTotalAssetsCap(740 ether);

        // 6. Transfer ownership of CapManager to the mainnet 5/8 multisig
        capManProxy.setOwner(Mainnet.GOV_MULTISIG);

        // 7. Deploy Lido implementation
        uint256 claimDelay = 10 minutes;
        lidoARMImpl = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay, 0, 0);
        _recordDeployment("LIDO_ARM_IMPL", address(lidoARMImpl));

        // 8. Deploy the Zapper
        zapper = new ZapperLidoARM(Mainnet.WETH, Mainnet.LIDO_ARM);
        zapper.setOwner(Mainnet.STRATEGIST);
        _recordDeployment("LIDO_ARM_ZAPPER", address(zapper));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Update Lido ARM");
        govProposal.action(resolver.implementations("LIDO_ARM"), "upgradeTo(address)", abi.encode(address(lidoARMImpl)));
    }
}
