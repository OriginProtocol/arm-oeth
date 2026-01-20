// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract imports
import {IERC20, IWETH, LegacyAMM} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {Proxy} from "contracts/Proxy.sol";
import {ZapperLidoARM} from "contracts/ZapperLidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment imports
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract UpgradeLidoARMMainnetScript is AbstractDeployScript("003_UpgradeLidoARMScript") {
    using GovHelper for GovProposal;

    bool public override skip = false;
    bool public constant override proposalExecuted = true;

    Proxy lidoARMProxy;
    Proxy capManProxy;
    LidoARM lidoARMImpl;
    LidoARM lidoARM;
    CapManager capManager;
    ZapperLidoARM zapper;

    function _execute() internal override {
        // 1. Record the proxy address used for AMM v1
        _recordDeployment("LIDO_ARM", Mainnet.LIDO_ARM);
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

    function _buildGovernanceProposal() internal override {}

    function _fork() internal override {
        vm.startPrank(Mainnet.ARM_MULTISIG);

        if (lidoARMProxy == Proxy(payable(address(0)))) {
            revert("Lido ARM proxy not found");
        }

        // remove all liquidity from the old AMM v1 contract
        uint256 wethLegacyBalance = IERC20(Mainnet.WETH).balanceOf(Mainnet.LIDO_ARM);
        if (wethLegacyBalance > 0) {
            LegacyAMM(Mainnet.LIDO_ARM).transferToken(Mainnet.WETH, Mainnet.ARM_MULTISIG, wethLegacyBalance);
        }
        uint256 stethLegacyBalance = IERC20(Mainnet.STETH).balanceOf(Mainnet.LIDO_ARM);
        if (stethLegacyBalance > 0) {
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

        // Approve the Lido ARM proxy to spend WETH
        IERC20(Mainnet.WETH).approve(address(lidoARMProxy), type(uint256).max);

        // upgrade and initialize the Lido ARM
        lidoARMProxy.upgradeToAndCall(address(lidoARMImpl), data);
        lidoARM = LidoARM(payable(Mainnet.LIDO_ARM));

        // Set the price that buy and sell prices can not cross
        LidoARM(payable(Mainnet.LIDO_ARM)).setCrossPrice(0.9998e36);

        // Set the buy price with a 2.5 basis point discount.
        // The sell price has a 1 basis point discount.
        LidoARM(payable(Mainnet.LIDO_ARM)).setPrices(0.99975e36, 0.9999e36);

        // transfer ownership of the Lido ARM proxy to the mainnet 5/8 multisig
        lidoARMProxy.setOwner(Mainnet.GOV_MULTISIG);

        // Deposit 10 WETH to the Lido ARM
        lidoARM.deposit(10 ether);

        vm.stopPrank();
    }
}
