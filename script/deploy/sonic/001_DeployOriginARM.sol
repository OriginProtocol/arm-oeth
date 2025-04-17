// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {CapManager} from "contracts/CapManager.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {ZapperARM} from "contracts/ZapperARM.sol";
import {Sonic} from "contracts/utils/Addresses.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract DeployOriginARMScript is AbstractDeployScript {
    string public constant override DEPLOY_NAME = "001_DeployOriginARMScript";
    bool public constant override proposalExecuted = false;

    Proxy capManProxy;
    CapManager capManager;
    Proxy originARMProxy;
    OriginARM originARMImpl;
    OriginARM originARM;
    ZapperARM zapper;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Deploy proxy for the Origin ARM
        originARMProxy = new Proxy();
        _recordDeploy("ORIGIN_ARM", address(originARMProxy));

        // 2. Deploy proxy for the CapManager
        capManProxy = new Proxy();
        _recordDeploy("ORIGIN_ARM_CAP_MAN", address(capManProxy));

        // 3. Deploy CapManager implementation
        CapManager capManagerImpl = new CapManager(address(originARMProxy));
        _recordDeploy("ORIGIN_ARM_CAP_IMPL", address(capManagerImpl));

        // 4. Initialize Proxy with CapManager implementation and set the owner to the deployer for now
        bytes memory data = abi.encodeWithSignature("initialize(address)", Sonic.RELAYER);
        capManProxy.initialize(address(capManagerImpl), deployer, data);
        capManager = CapManager(address(capManProxy));

        // 5. Set total wS cap
        capManager.setTotalAssetsCap(20000 ether);

        // 6. Transfer ownership of CapManager to the Sonic 5/8 Admin multisig
        capManProxy.setOwner(Sonic.ADMIN);

        // 7. Deploy new Origin ARM implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        originARMImpl = new OriginARM(Sonic.OS, Sonic.WS, Sonic.OS_VAULT, claimDelay);
        _recordDeploy("ORIGIN_ARM_IMPL", address(originARMImpl));

        // 8. Approve a little bit of wS to be transferred to the ARM proxy
        // This is needed for the initialize function which will mint some ARM LP tokens
        // and send to a dead address
        IERC20(Sonic.WS).approve(address(originARMProxy), 1e12);

        // 9. Initialize Proxy with Origin ARM implementation and set the owner to the deployer for now
        data = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address,address)",
            "Origin ARM",
            "ARM-WS-OS",
            Sonic.RELAYER,
            2000, // 20% fee
            Sonic.STRATEGIST,
            address(capManProxy)
        );
        originARMProxy.initialize(address(originARMImpl), deployer, data);
        originARM = OriginARM(address(originARMProxy));

        // 10. Set the supported lending markets
        address[] memory markets = new address[](2);
        markets[0] = Sonic.SILO_OS;
        markets[1] = Sonic.SILO_stS;
        originARM.addMarkets(markets);

        // 11. Transfer ownership of OriginARM to the Sonic 5/8 Admin multisig
        originARM.setOwner(Sonic.ADMIN);

        // 12. Deploy the Zapper
        zapper = new ZapperARM(Sonic.WS);
        zapper.setOwner(Sonic.ADMIN);
        _recordDeploy("ARM_ZAPPER", address(zapper));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {}

    function _fork() internal view override {
        if (this.isForked()) {}
    }
}
