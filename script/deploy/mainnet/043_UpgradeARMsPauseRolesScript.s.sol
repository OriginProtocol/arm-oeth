// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

/// @title Split the ARM pause and unpause roles
/// @notice Upgrades the WETH and USDC ARMs to the AbstractARM implementation that separates pausing
///         from unpausing, then wires the two new roles:
///           - `guardian` = 2/8 multisig, which hosts the threat-detection module. Can pause only.
///           - `adminMultisig` = 5/8 multisig. Can pause and unpause.
///         `owner` keeps doing upgrades and stays a valid caller on both, so governance is always a
///         fallback but never on the fast path. The result is that no single 2/8 key can both
///         re-open a paused ARM and change its code.
/// @dev Scope. Only the ARMs that can safely receive a current-source implementation are included:
///
///      - LIDO_ARM / ETHER_FI_ARM: their current source exceeds the EIP-170 runtime limit, so no new
///        implementation can be deployed for them at all.
///      - ETHENA_ARM: EXCLUDED because the deployed implementation's storage layout does not match
///        the current source. The deployed AbstractARM still carries the `_deprecatedTraderate0/1`,
///        `_deprecatedCrossPrice`, `_deprecatedWithdrawsQueued/Claimed` and
///        `_deprecatedLastAvailableAssets` placeholders, so on-chain `feeCollector` sits at slot 57,
///        `activeMarket` at 59 and `armBuffer` at 61. The current source places them at 59, 53 and 55.
///        Upgrading would therefore corrupt live state. This predates this change; script 034 only
///        avoids it because its idempotency check short-circuits before upgrading.
///      - OETH_ARM (legacy, no pause) and ETH_ARM (unused, holds only the dead-shares seed).
///
///      Both ARMs in scope are owned by a multisig directly, so no governance proposal is needed.
contract $043_UpgradeARMsPauseRolesScript is AbstractDeployScript("043_UpgradeARMsPauseRolesScript") {
    MultiAssetARM public wethARMImpl;
    MultiAssetARM public usdcARMImpl;

    function _execute() internal override {
        uint256 claimDelay = 10 minutes;

        // Constructor args are unchanged from the scripts that deployed the current implementations
        // (038 for WETH, 039 for USDC) so the pause roles are the only behavioural change.

        wethARMImpl = new MultiAssetARM({
            _liquidityAsset: Mainnet.WETH, _claimDelay: claimDelay, _minSharesToRedeem: 1e7, _allocateThreshold: 1 ether
        });
        _recordDeployment("WETH_ARM_IMPL", address(wethARMImpl));

        usdcARMImpl = new MultiAssetARM({
            _liquidityAsset: Mainnet.USDC, _claimDelay: claimDelay, _minSharesToRedeem: 1e6, _allocateThreshold: 100e6
        });
        _recordDeployment("USDC_ARM_IMPL", address(usdcARMImpl));
    }

    /// @notice Both ARMs are owned by a multisig directly, so we simulate their upgrade with a prank.
    ///         On real deployment the multisig executes upgradeTo + setPauseRoles as a single batched
    ///         Safe transaction. Batching matters: between the two calls the role slots are still
    ///         address(0), so unpause would briefly narrow back to owner-only.
    function _fork() internal override {
        _upgradeAndSetRoles("WETH_ARM", "WETH_ARM_IMPL");
        _upgradeAndSetRoles("USDC_ARM", "USDC_ARM_IMPL");

        // Behavioural assertions (2/8 can pause but not unpause, 5/8 can unpause) live in the smoke
        // tests. They must not run here: _fork() executes inside the test's setUp(), so anything
        // that mutates ARM state or arms a vm.expectRevert would leak into the test body.
        _assertRolesSet("WETH_ARM");
        _assertRolesSet("USDC_ARM");
    }

    function _upgradeAndSetRoles(string memory proxyName, string memory implementationName) internal {
        Proxy armProxy = Proxy(payable(resolver.resolve(proxyName)));
        address armImpl = resolver.resolve(implementationName);

        // Idempotent: the deployment runner can replay pending multisig actions on forks.
        if (armProxy.implementation() == armImpl) return;

        // Guard the storage assumption this upgrade depends on. The new `guardian` and
        // `adminMultisig` occupy slots 62 and 63, taken from the AbstractARM gap. If the deployed
        // layout ever diverges from the current source, those slots hold live data and this upgrade
        // would corrupt it, so fail loudly instead. This is exactly the condition that rules
        // ETHENA_ARM out of scope.
        require(vm.load(address(armProxy), bytes32(uint256(62))) == 0, "slot 62 not free");
        require(vm.load(address(armProxy), bytes32(uint256(63))) == 0, "slot 63 not free");

        // Prank the live owner rather than a hardcoded Safe. Ownership of these proxies has moved
        // since they were deployed, so the deploy scripts are not the source of truth for it.
        vm.startPrank(armProxy.owner());
        armProxy.upgradeTo(armImpl);
        AbstractARM(payable(address(armProxy))).setPauseRoles(Mainnet.MULTISIG_2_OF_8, Mainnet.MULTISIG_5_OF_8);
        vm.stopPrank();
    }

    /// @dev Confirm the roles landed. Read-only: this must not mutate ARM state, because the smoke
    ///      tests run against whatever state _fork() leaves behind.
    function _assertRolesSet(string memory proxyName) internal view {
        AbstractARM arm = AbstractARM(payable(resolver.resolve(proxyName)));

        require(arm.guardian() == Mainnet.MULTISIG_2_OF_8, "guardian not set");
        require(arm.adminMultisig() == Mainnet.MULTISIG_5_OF_8, "adminMultisig not set");
    }
}
