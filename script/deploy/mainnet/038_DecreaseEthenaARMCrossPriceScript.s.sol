// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {IERC20, IStakedUSDe} from "contracts/Interfaces.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {EthenaAssetAdapter} from "contracts/adapters/EthenaAssetAdapter.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {State} from "script/deploy/helpers/DeploymentTypes.sol";
import {GovHelper, GovProposal} from "script/deploy/helpers/GovHelper.sol";

/// @title Decrease the Ethena ARM sUSDe cross price
/// @notice Builds a governance proposal that lowers the price used to value sUSDe in USDe.
///         There is nothing to deploy; the governance-owned Ethena ARM is updated directly.
/// @dev Lowering the cross price is only allowed once both the ARM's sUSDe balance and its pending
///      sUSDe redemption exposure have been cleared. The operator must complete those steps before
///      executing the proposal. Fork runs reproduce that operational preparation before simulating
///      the governance lifecycle.
contract $038_DecreaseEthenaARMCrossPriceScript is AbstractDeployScript("038_DecreaseEthenaARMCrossPriceScript") {
    using GovHelper for GovProposal;

    bool public constant override skip = false;

    /// @dev 0.9999e36 = 0.9999 USDe per sUSDe (a 1 basis point discount to parity).
    uint256 internal constant CROSS_PRICE = 0.9999e36;

    function _execute() internal override {
        if (state != State.REAL_DEPLOYING) _prepareForkState();
    }

    function _buildGovernanceProposal() internal override {
        govProposal.setDescription("Decrease Ethena ARM sUSDe cross price to 0.9999 USDe");
        govProposal.action(
            resolver.resolve("ETHENA_ARM"), "setCrossPrice(address,uint256)", abi.encode(Mainnet.SUSDE, CROSS_PRICE)
        );
    }

    /// @dev Models the operator clearing all sUSDe exposure before governance executes. This is fork-only:
    ///      no operational transaction is broadcast by this proposal script on mainnet.
    function _prepareForkState() internal {
        EthenaARM arm = EthenaARM(payable(resolver.resolve("ETHENA_ARM")));
        EthenaAssetAdapter adapter = EthenaAssetAdapter(resolver.resolve("ETHENA_ARM_SUSDE_ADAPTER"));

        // AbstractDeployScript starts a deployer prank before _execute(). Replace it with the actors
        // involved in the operational preparation, then restore it before returning.
        vm.stopPrank();

        // Let every existing Ethena cooldown mature, then claim the complete FIFO queue.
        vm.warp(block.timestamp + 7 days);
        uint256 pendingShares;
        for (uint256 i; i < adapter.MAX_UNSTAKERS(); ++i) {
            pendingShares += adapter.requestShares(adapter.unstakers(i));
        }
        if (pendingShares != 0) {
            vm.prank(arm.operator());
            arm.claimBaseAssetRedeem(Mainnet.SUSDE, pendingShares);
        }

        // Model a trader buying the ARM's remaining sUSDe at the configured sell price.
        IERC20 usde = IERC20(Mainnet.USDE);
        IERC20 susde = IERC20(Mainnet.SUSDE);
        uint256 susdeBalance = susde.balanceOf(address(arm));
        if (susdeBalance != 0) {
            uint256 usdeRequired = IStakedUSDe(Mainnet.SUSDE).convertToAssets(susdeBalance) + 1 ether;
            // USDe inherits OpenZeppelin ERC20 with `_balances` at storage slot 2. This fork-only
            // write is the lightweight equivalent of forge-std's deal() helper.
            vm.store(Mainnet.USDE, keccak256(abi.encode(address(this), uint256(2))), bytes32(usdeRequired));
            usde.approve(address(arm), usdeRequired);
            arm.swapTokensForExactTokens(usde, susde, susdeBalance, usdeRequired, address(this));
        }

        vm.startPrank(deployer);
    }
}
