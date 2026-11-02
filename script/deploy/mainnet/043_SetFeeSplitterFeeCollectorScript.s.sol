// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";
import {IFeeSplitter} from "contracts/Interfaces.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

/// @title Send active ARM fees to the FeeSplitter
/// @notice Points the active ARMs' fee collector at the Origin FeeSplitter, so ARM fees follow
///         the OUSD/OETH fees to the OGN buyback. Nothing is deployed.
///         - Lido, WETH and Ethena ARMs are Timelock-owned, so they go through governance.
///         - The USDC ARM is owned by the 5/8. That's a Safe tx, simulated in _fork().
///         - FeeSplitter.addAsset(USDe) is a 2/8 tx on origin-dollar. Also simulated in _fork().
/// @dev collectFees() is kept out of the proposal on purpose. It reverts with InsufficientLiquidity
///      when an ARM's cash is in Morpho or reserved for withdrawals, and one revert fails the whole
///      proposal. Fees already accrued go to the FeeSplitter on the next collect anyway.
contract $043_SetFeeSplitterFeeCollectorScript is AbstractDeployScript("043_SetFeeSplitterFeeCollectorScript") {
    using GovHelper for GovProposal;

    bool public constant override skip = false;

    /// @dev 20e18 = 20 USDe. Matches the OGN CoW harvester's minSellAmount for USDe.
    uint256 internal constant USDE_MIN_DISTRIBUTE = 20e18;

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Send Lido, WETH and Ethena ARM fees to the FeeSplitter");

        bytes memory data = abi.encode(Mainnet.FEE_SPLITTER);
        govProposal.action(resolver.resolve("LIDO_ARM"), "setFeeCollector(address)", data);
        govProposal.action(resolver.resolve("WETH_ARM"), "setFeeCollector(address)", data);
        govProposal.action(resolver.resolve("ETHENA_ARM"), "setFeeCollector(address)", data);
    }

    function _fork() internal override {
        IFeeSplitter splitter = IFeeSplitter(Mainnet.FEE_SPLITTER);

        // 2/8 Safe tx on origin-dollar. Guarded: fork runs replay this while governance is pending.
        if (!splitter.isSupported(Mainnet.USDE)) {
            vm.prank(Mainnet.MULTISIG_2_OF_8);
            splitter.addAsset(Mainnet.USDE, USDE_MIN_DISTRIBUTE);
        }

        // 5/8 Safe tx. Not part of the proposal.
        AbstractARM usdcARM = AbstractARM(payable(resolver.resolve("USDC_ARM")));
        if (usdcARM.feeCollector() != Mainnet.FEE_SPLITTER) {
            require(usdcARM.owner() == Mainnet.MULTISIG_5_OF_8, "Unexpected USDC ARM owner");
            vm.prank(Mainnet.MULTISIG_5_OF_8);
            usdcARM.setFeeCollector(Mainnet.FEE_SPLITTER);
        }

        _checkARM(splitter, "LIDO_ARM");
        _checkARM(splitter, "WETH_ARM");
        _checkARM(splitter, "ETHENA_ARM");
        _checkARM(splitter, "USDC_ARM");
    }

    function _checkARM(IFeeSplitter splitter, string memory name) internal view {
        AbstractARM arm = AbstractARM(payable(resolver.resolve(name)));
        require(arm.feeCollector() == Mainnet.FEE_SPLITTER, string.concat(name, ": fee collector not set"));
        // Catches a fee asset the splitter would never distribute.
        require(splitter.isSupported(arm.liquidityAsset()), string.concat(name, ": fee asset not on FeeSplitter"));
    }
}
