// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {EthenaAssetAdapter} from "contracts/adapters/EthenaAssetAdapter.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Resolver} from "script/deploy/helpers/Resolver.sol";
import {State} from "script/deploy/helpers/DeploymentTypes.sol";
import {$044_UpgradeEthenaAssetAdapterScript} from "script/deploy/mainnet/044_UpgradeEthenaAssetAdapterScript.s.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

/// @dev The pinned ARM implementation predates the baseAssetDecimals return field.
interface IHistoricalEthenaConfig {
    function baseAssetConfigs(address base)
        external
        view
        returns (uint128, uint128, uint128, uint128, uint128, uint128 pendingAssets, bool, address);
}

contract Fork_EthenaDualCooldownUpgrade_Test is Test {
    function _pendingAssets(EthenaARM arm) internal view returns (uint256 assets) {
        (,,,,, assets,,) = IHistoricalEthenaConfig(address(arm)).baseAssetConfigs(Mainnet.SUSDE);
    }

    function _runUpgrade(EthenaAssetAdapter adapter, EthenaARM arm) internal {
        Resolver resolver = Resolver(address(uint160(uint256(keccak256("Resolver")))));
        vm.etch(address(resolver), type(Resolver).runtimeCode);
        resolver.setState(State.FORK_TEST);
        resolver.addContract("ETHENA_ARM", address(arm));
        resolver.addContract("ETHENA_ARM_SUSDE_ADAPTER", address(adapter));
        $044_UpgradeEthenaAssetAdapterScript script = new $044_UpgradeEthenaAssetAdapterScript();
        // Rehearse operator preparation at the historical quote, preserving buy price and remaining limits.
        (uint128 buy, uint128 sell, uint128 buyLimit, uint128 sellLimit,,,,) =
            IHistoricalEthenaConfig(address(arm)).baseAssetConfigs(Mainnet.SUSDE);
        if (sell < 1e36) {
            vm.prank(arm.operator());
            arm.setPrices(Mainnet.SUSDE, buy, 1e36, buyLimit, sellLimit);
        }
        script.run();
        (,,,, uint128 crossPrice,,,) = IHistoricalEthenaConfig(address(arm)).baseAssetConfigs(Mainnet.SUSDE);
        assertEq(crossPrice, 1e36);
        assertEq(Proxy(payable(address(adapter))).implementation(), resolver.resolve("ETHENA_ARM_SUSDE_ADAPTER_IMPL"));
    }

    function test_UpgradeWithTwoOutstandingNativeRequests() public {
        vm.createSelectFork("mainnet", 26_502_548);
        EthenaAssetAdapter adapter = EthenaAssetAdapter(0xE620aFB67223AE03C260112aE21A717Af94C90f0);
        EthenaARM arm = EthenaARM(payable(adapter.arm()));
        Proxy proxy = Proxy(payable(address(adapter)));
        uint256 shares;
        uint256 expected;
        uint256 pending;
        for (uint256 i; i < adapter.MAX_UNSTAKERS(); ++i) {
            address slot = adapter.unstakers(i);
            if (adapter.requestShares(slot) == 0) continue;
            shares += adapter.requestShares(slot);
            expected += adapter.requestAssets(slot);
            ++pending;
        }
        assertEq(pending, 2);
        assertEq(proxy.owner(), Mainnet.TIMELOCK);
        assertEq(_pendingAssets(arm), expected);
        _runUpgrade(adapter, arm);
        assertEq(_pendingAssets(arm), expected);
        assertEq(proxy.owner(), Mainnet.TIMELOCK);
        assertEq(adapter.susde().cooldownDuration(), 0);
        uint256 beforeClaim = adapter.usde().balanceOf(address(arm));
        address operator = arm.operator();
        vm.prank(operator);
        (uint256 claimed, uint256 recorded, uint256 received) = arm.claimBaseAssetRedeem(Mainnet.SUSDE, shares);
        assertEq(claimed, shares);
        assertEq(recorded, expected);
        assertEq(_pendingAssets(arm), 0);
        assertEq(received, expected);
        assertApproxEqAbs(received, 45_068.25 ether, 0.005 ether);
        assertEq(adapter.usde().balanceOf(address(arm)), beforeClaim + received);

        skip(adapter.DELAY_REQUEST());
        deal(Mainnet.SUSDE, address(arm), 1 ether);
        address nextSlot = adapter.unstakers(adapter.nextUnstakerIndex());
        vm.startPrank(operator);
        (, uint256 funded) = arm.requestBaseAssetRedeem(Mainnet.SUSDE, 1 ether);
        assertTrue(adapter.isPrefunded(nextSlot));
        assertEq(_pendingAssets(arm), funded);
        (,, received) = arm.claimBaseAssetRedeem(Mainnet.SUSDE, 1 ether);
        vm.stopPrank();
        assertEq(received, funded);
        assertEq(_pendingAssets(arm), 0);
        assertFalse(adapter.isPrefunded(nextSlot));
    }
}
