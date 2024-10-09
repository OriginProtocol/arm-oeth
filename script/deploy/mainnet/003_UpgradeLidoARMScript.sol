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
    bool public constant override proposalExecuted = false;

    Proxy lidoARMProxy;
    Proxy capManProxy;
    LidoARM lidoARMImpl;
    CapManager capManager;

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

        // 5. Set the liquidity Provider caps
        capManager.setTotalAssetsCap(100 ether);
        address[] memory liquidityProviders = new address[](1);
        liquidityProviders[0] = Mainnet.TREASURY;
        capManager.setLiquidityProviderCaps(liquidityProviders, 100 ether);

        // 6. Deploy Lido implementation
        uint256 claimDelay = tenderlyTestnet ? 1 minutes : 10 minutes;
        lidoARMImpl = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, claimDelay);
        _recordDeploy("LIDO_ARM_IMPL", address(lidoARMImpl));

        // 7. Transfer ownership of CapManager to the mainnet 5/8 multisig
        capManProxy.setOwner(Mainnet.GOV_MULTISIG);

        // 8. Deploy the Zapper
        ZapperLidoARM zapper = new ZapperLidoARM(Mainnet.WETH, Mainnet.LIDO_ARM);
        zapper.setOwner(Mainnet.STRATEGIST);
        _recordDeploy("LIDO_ARM_ZAPPER", address(zapper));

        console.log("Finished deploying", DEPLOY_NAME);

        // Post deploy
        // 1. The Lido ARM multisig needs to set the owner to the mainnet 5/8 multisig
        // 1. The mainnet 5/8 multisig needs to upgrade and call initialize on the Lido ARM
        // 2. the Relayer needs to set the swap prices
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
            console.log("Withdrawing WETH from legacy Lido ARM");
            LegacyAMM(Mainnet.LIDO_ARM).transferToken(Mainnet.WETH, Mainnet.ARM_MULTISIG, wethLegacyBalance);
        }
        uint256 stethLegacyBalance = IERC20(Mainnet.STETH).balanceOf(Mainnet.LIDO_ARM);
        if (stethLegacyBalance > 0) {
            console.log("Withdrawing stETH from legacy Lido ARM");
            LegacyAMM(Mainnet.LIDO_ARM).transferToken(Mainnet.STETH, Mainnet.ARM_MULTISIG, stethLegacyBalance);
        }
        // TODO need to also remove anything in the Lido withdrawal queue

        // Initialize Lido ARM proxy and implementation contract
        bytes memory data = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address,address)",
            "Lido ARM",
            "ARM-ST",
            Mainnet.ARM_RELAYER,
            1500, // 15% performance fee
            Mainnet.ARM_BUYBACK,
            address(capManProxy)
        );
        console.log("lidoARM initialize data:");
        console.logBytes(data);

        uint256 tinyMintAmount = 1e12;

        // Get some WETH which has already been done on mainnet
        // vm.deal(Mainnet.ARM_MULTISIG, tinyMintAmount);
        // IWETH(Mainnet.WETH).deposit{value: tinyMintAmount}();

        // Approve the Lido ARM proxy to spend WETH
        IERC20(Mainnet.WETH).approve(address(lidoARMProxy), tinyMintAmount);

        // upgrade and initialize the Lido ARM
        lidoARMProxy.upgradeToAndCall(address(lidoARMImpl), data);

        // Set the price that buy and sell prices can not cross
        LidoARM(payable(Mainnet.LIDO_ARM)).setCrossPrice(0.9998e36);

        // Set the buy price with a 8 basis point discount. The sell price is 1.0
        LidoARM(payable(Mainnet.LIDO_ARM)).setPrices(0.9994e36, 0.9998e36);

        // transfer ownership of the Lido ARM proxy to the mainnet 5/8 multisig
        lidoARMProxy.setOwner(Mainnet.GOV_MULTISIG);

        console.log("Finished running initializing Lido ARM as ARM_MULTISIG");

        if (tenderlyTestnet) {
            vm.stopBroadcast();
        } else {
            vm.stopPrank();
        }

        if (tenderlyTestnet) {
            console.log("Broadcasting fork script to Tenderly as: %s", Mainnet.ARM_RELAYER);
            vm.startBroadcast(Mainnet.ARM_RELAYER);
        } else {
            vm.startPrank(Mainnet.ARM_RELAYER);
        }

        // Add some test liquidity providers
        address[] memory testProviders = new address[](1);
        testProviders[0] = 0x3bB354a1E0621F454c5D5CE98f6ea21a53bf2d7d;
        capManager.setLiquidityProviderCaps(testProviders, 100 ether);

        if (tenderlyTestnet) {
            vm.stopBroadcast();
        } else {
            vm.stopPrank();
        }
    }
}
