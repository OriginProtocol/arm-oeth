// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {IERC20, IWETH, LegacyAMM} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {LiquidityProviderController} from "contracts/LiquidityProviderController.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {GovProposal, GovSixHelper} from "contracts/utils/GovSixHelper.sol";
import {AbstractDeployScript} from "../AbstractDeployScript.sol";

contract UpgradeLidoARMMainnetScript is AbstractDeployScript {
    using GovSixHelper for GovProposal;

    GovProposal public govProposal;

    string public constant override DEPLOY_NAME = "003_UpgradeLidoARMScript";
    bool public constant override proposalExecuted = false;

    Proxy lidoARMProxy;
    Proxy lpcProxy;
    LidoARM lidoARMImpl;

    function _execute() internal override {
        console.log("Deploy:", DEPLOY_NAME);
        console.log("------------");

        // 1. Record the proxy address used for AMM v1
        _recordDeploy("LIDO_ARM", Mainnet.LIDO_ARM);
        lidoARMProxy = Proxy(Mainnet.LIDO_ARM);

        // 2. Deploy proxy for the Liquidity Provider Controller
        lpcProxy = new Proxy();
        _recordDeploy("LIDO_ARM_LPC", address(lpcProxy));

        // 3. Deploy Liquidity Provider Controller implementation
        LiquidityProviderController lpcImpl = new LiquidityProviderController(address(lidoARMProxy));
        _recordDeploy("LIDO_ARM_LPC_IMPL", address(lpcImpl));

        // 4. Initialize Proxy with LiquidityProviderController implementation and set the owner to the deployer for now
        bytes memory data = abi.encodeWithSignature("initialize(address)", Mainnet.ARM_RELAYER);
        lpcProxy.initialize(address(lpcImpl), deployer, data);
        LiquidityProviderController liquidityProviderController = LiquidityProviderController(address(lpcProxy));

        // 5. Set the liquidity Provider caps
        liquidityProviderController.setTotalAssetsCap(10 ether);
        address[] memory liquidityProviders = new address[](1);
        liquidityProviders[0] = Mainnet.TREASURY;
        liquidityProviderController.setLiquidityProviderCaps(liquidityProviders, 10 ether);

        // 6. Deploy Lido implementation
        lidoARMImpl = new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL);
        _recordDeploy("LIDO_ARM_IMPL", address(lidoARMImpl));

        // 7. Transfer ownership of LiquidityProviderController to the mainnet 5/8 multisig
        lpcProxy.setOwner(Mainnet.GOV_MULTISIG);

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
            console.log("Executing fork script against a fork as: %s", Mainnet.ARM_MULTISIG);
            vm.startPrank(Mainnet.ARM_MULTISIG);
        }

        if (lidoARMProxy == Proxy(0x0000000000000000000000000000000000000000)) {
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
            address(lpcProxy)
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

        // Set the buy price with a 8 basis point discount. The sell price is 1.0
        LidoARM(payable(Mainnet.LIDO_ARM)).setPrices(9994e32, 1e36);

        // transfer ownership of the Lido ARM proxy to the mainnet 5/8 multisig
        lidoARMProxy.setOwner(Mainnet.GOV_MULTISIG);

        console.log("Finished running initializing Lido ARM as ARM_MULTISIG");

        if (tenderlyTestnet) {
            vm.stopBroadcast();
        } else {
            vm.stopPrank();
        }
    }
}
