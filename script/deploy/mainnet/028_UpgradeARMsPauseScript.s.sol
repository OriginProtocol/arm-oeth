// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

/// @notice Upgrades LidoARM, EtherFiARM, EthenaARM and OETH (Origin) ARM
/// to the new AbstractARM implementation that adds the pause mechanism
/// (pause/unpause + whenNotPaused on deposit/requestRedeem) and lets
/// the operator claim withdrawal requests on behalf of users.
contract $028_UpgradeARMsPauseScript is AbstractDeployScript("028_UpgradeARMsPauseScript") {
    using GovHelper for GovProposal;

    LidoARM public lidoARMImpl;
    EtherFiARM public etherFiARMImpl;
    EthenaARM public ethenaARMImpl;

    function _execute() internal override {
        uint256 claimDelay = 10 minutes;

        // 1. LidoARM
        lidoARMImpl = new LidoARM(
            Mainnet.STETH,
            Mainnet.WETH,
            Mainnet.LIDO_WITHDRAWAL,
            claimDelay,
            1e7, // minSharesToRedeem
            1e18 // allocateThreshold
        );
        _recordDeployment("LIDO_ARM_IMPL", address(lidoARMImpl));

        // 2. EtherFiARM
        etherFiARMImpl = new EtherFiARM(
            Mainnet.EETH,
            Mainnet.WETH,
            Mainnet.ETHERFI_WITHDRAWAL,
            claimDelay,
            1e7, // minSharesToRedeem
            1e18, // allocateThreshold
            Mainnet.ETHERFI_WITHDRAWAL_NFT
        );
        _recordDeployment("ETHERFI_ARM_IMPL", address(etherFiARMImpl));

        // 3. EthenaARM
        ethenaARMImpl = new EthenaARM(
            Mainnet.USDE,
            Mainnet.SUSDE,
            claimDelay,
            1e18, // minSharesToRedeem
            100e18 // allocateThreshold
        );
        _recordDeployment("ETHENA_ARM_IMPL", address(ethenaARMImpl));
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Upgrade LidoARM to add pause mechanism and operator-claim");

        govProposal.action(
            resolver.resolve("LIDO_ARM"), "upgradeTo(address)", abi.encode(resolver.resolve("LIDO_ARM_IMPL"))
        );
    }

    /// @notice EtherFiARM and EthenaARM are owned by the multisig directly, so we upgrade them
    /// via a prank in fork simulation. On real deployment, the multisig will execute the upgrade.
    function _fork() internal override {
        // EtherFiARM
        Proxy etherFiProxy = Proxy(payable(resolver.resolve("ETHER_FI_ARM")));
        address etherFiImpl = resolver.resolve("ETHERFI_ARM_IMPL");
        if (etherFiProxy.implementation() != etherFiImpl) {
            vm.startPrank(etherFiProxy.owner());
            etherFiProxy.upgradeTo(etherFiImpl);
            vm.stopPrank();
        }

        // EthenaARM
        Proxy ethenaProxy = Proxy(payable(resolver.resolve("ETHENA_ARM")));
        address ethenaImpl = resolver.resolve("ETHENA_ARM_IMPL");
        if (ethenaProxy.implementation() != ethenaImpl) {
            vm.startPrank(ethenaProxy.owner());
            ethenaProxy.upgradeTo(ethenaImpl);
            vm.stopPrank();
        }
    }
}
