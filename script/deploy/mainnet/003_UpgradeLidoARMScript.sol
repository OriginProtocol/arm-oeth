// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {IERC20, IWETH, LegacyAMM} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {Proxy} from "contracts/Proxy.sol";
import {ZapperLidoARM} from "contracts/ZapperLidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeLidoARMMainnetScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "003_UpgradeLidoARMScript";
    bool public constant override proposalExecuted = true;

    Proxy lidoARMProxy;
    Proxy capManProxy;
    LidoARM lidoARMImpl;
    LidoARM lidoARM;
    CapManager capManager;
    ZapperLidoARM zapper;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Record the proxy address used for AMM v1
        _recordDeploy("LIDO_ARM", Mainnet.LIDO_ARM);
        lidoARMProxy = Proxy(payable(Mainnet.LIDO_ARM));

        // 2. Deploy proxy for the CapManager
        capManProxy = new Proxy();
        _recordDeploy("LIDO_ARM_CAP_MAN", address(capManProxy));

        // 3. Deploy CapManager implementation
        CapManager capManagerImpl = new CapManager(address(lidoARMProxy));
        _recordDeploy("LIDO_ARM_CAP_IMPL", address(capManagerImpl));

        // 4. Initialize Proxy with CapManager implementation and set the owner to the deployer for now
        bytes memory data = abi.encodeWithSignature("initialize(address)", Mainnet.ARM_RELAYER);
        capManProxy.initialize(address(capManagerImpl), deployer, data);
        capManager = CapManager(address(capManProxy));

        // 5. Set total assets cap
        capManager.setTotalAssetsCap(740 ether);

        // 6. Transfer ownership of CapManager to the mainnet 5/8 multisig
        capManProxy.setOwner(Mainnet.GOV_MULTISIG);

        // 7. Deploy Lido implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        lidoARMImpl = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay);
        _recordDeploy("LIDO_ARM_IMPL", address(lidoARMImpl));

        // 8. Deploy the Zapper
        zapper = new ZapperLidoARM(Mainnet.WETH, Mainnet.LIDO_ARM);
        zapper.setOwner(Mainnet.STRATEGIST);
        _recordDeploy("LIDO_ARM_ZAPPER", address(zapper));

        console.log("Finished deploying", DEPLOY_NAME);
    }

    function _buildGovernanceProposal() internal override {}

    function _fork() internal override {
        if (tenderlyTestnet) {
            console.log("Broadcasting fork script to Tenderly as: %s", Mainnet.ARM_MULTISIG);
            vm.startBroadcast(Mainnet.ARM_MULTISIG);
        } else {
            vm.startPrank(Mainnet.ARM_MULTISIG);
        }

        if (lidoARMProxy == Proxy(payable(address(0)))) {
            revert("Lido ARM proxy not found");
        }

        // remove all liquidity from the old AMM v1 contract
        uint256 wethLegacyBalance = IERC20(Mainnet.WETH).balanceOf(Mainnet.LIDO_ARM);
        if (wethLegacyBalance > 0) {
            console.log("About to withdraw WETH from legacy Lido ARM");
            LegacyAMM(Mainnet.LIDO_ARM).transferToken(Mainnet.WETH, Mainnet.ARM_MULTISIG, wethLegacyBalance);
        }
        uint256 stethLegacyBalance = IERC20(Mainnet.STETH).balanceOf(Mainnet.LIDO_ARM);
        if (stethLegacyBalance > 0) {
            console.log("About to withdraw stETH from legacy Lido ARM");
            LegacyAMM(Mainnet.LIDO_ARM).transferToken(Mainnet.STETH, Mainnet.ARM_MULTISIG, stethLegacyBalance);
        }
        // need to also remove anything in the Lido withdrawal queue

        // Initialize Lido ARM proxy and implementation contract
        bytes memory data = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address,address)",
            "Lido ARM",
            "ARM-WETH-stETH",
            Mainnet.ARM_RELAYER,
            2000, // 20% performance fee
            Mainnet.ARM_BUYBACK,
            address(capManProxy)
        );
        console.log("LidoARM initialize data:");
        console.logBytes(data);

        // Get some WETH which has already been done on mainnet
        // uint256 tinyMintAmount = 1e12;
        // vm.deal(Mainnet.ARM_MULTISIG, tinyMintAmount);
        // IWETH(Mainnet.WETH).deposit{value: tinyMintAmount}();

        // Approve the Lido ARM proxy to spend WETH
        IERC20(Mainnet.WETH).approve(address(lidoARMProxy), type(uint256).max);

        // upgrade and initialize the Lido ARM
        console.log("About to upgrade the ARM contract");
        lidoARMProxy.upgradeToAndCall(address(lidoARMImpl), data);
        lidoARM = LidoARM(payable(Mainnet.LIDO_ARM));

        // Set the price that buy and sell prices can not cross
        console.log("About to set the cross price on the ARM contract");
        LidoARM(payable(Mainnet.LIDO_ARM)).setCrossPrice(0.9998e36);

        // Set the buy price with a 2.5 basis point discount.
        // The sell price has a 1 basis point discount.
        console.log("About to set prices on the ARM contract");
        LidoARM(payable(Mainnet.LIDO_ARM)).setPrices(0.99975e36, 0.9999e36);

        // transfer ownership of the Lido ARM proxy to the mainnet 5/8 multisig
        console.log("About to set ARM owner to", Mainnet.GOV_MULTISIG);
        lidoARMProxy.setOwner(Mainnet.GOV_MULTISIG);

        // Deposit 10 WETH to the Lido ARM
        console.log("About to deposit 10 WETH into the ARM contract", Mainnet.GOV_MULTISIG);
        lidoARM.deposit(10 ether);

        console.log("Finished running initializing Lido ARM as ARM_MULTISIG");

        if (tenderlyTestnet) {
            vm.stopBroadcast();
        } else {
            vm.stopPrank();
        }
    }
}
