// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {$030_UpgradeLidoARMSwapFeeScript} from "script/deploy/mainnet/030_UpgradeLidoARMSwapFeeScript.s.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

contract ExposedUpgradeLidoARMSwapFeeScript is $030_UpgradeLidoARMSwapFeeScript {
    function migrateLegacyWithdrawQueueData() external pure returns (bytes memory) {
        return _migrateLegacyWithdrawQueueData();
    }
}

contract LidoUpgradeGuardsTest is Test {
    uint256 internal constant LEGACY_PACKED_WITHDRAW_QUEUE_SLOT = 53;
    uint256 internal constant NEXT_WITHDRAWAL_INDEX_SLOT = 54;
    uint256 internal constant LIDO_LEGACY_WITHDRAWAL_QUEUE_AMOUNT_SLOT = 100;

    ExposedUpgradeLidoARMSwapFeeScript internal script;

    function setUp() external {
        script = new ExposedUpgradeLidoARMSwapFeeScript();
    }

    function test_UpgradeDataCallsLegacyWithdrawQueueMigration() external view {
        assertEq(
            script.migrateLegacyWithdrawQueueData(),
            abi.encodeWithSelector(AbstractARM.migrateLegacyWithdrawQueue.selector)
        );
    }

    function test_UpgradeToAndCallMigratesWithClaimedLegacyWithdrawQueue() external {
        (Proxy proxy, LidoARM newImpl) = _deployInitializedLidoARMProxy();
        uint256 packedLegacyQueue = _packLegacyWithdrawQueue(1 ether, 1 ether);
        vm.store(address(proxy), bytes32(LEGACY_PACKED_WITHDRAW_QUEUE_SLOT), bytes32(packedLegacyQueue));
        vm.store(address(proxy), bytes32(NEXT_WITHDRAWAL_INDEX_SLOT), bytes32(uint256(3)));

        proxy.upgradeToAndCall(address(newImpl), script.migrateLegacyWithdrawQueueData());

        assertEq(LidoARM(payable(address(proxy))).reservedWithdrawLiquidity(), 0);
        assertEq(LidoARM(payable(address(proxy))).legacyWithdrawalRequestCount(), 3);
        assertEq(uint256(vm.load(address(proxy), bytes32(LEGACY_PACKED_WITHDRAW_QUEUE_SLOT))), packedLegacyQueue);
    }

    function test_RevertWhen_UpgradeToAndCall_LegacyLidoWithdrawalRequestsPending() external {
        (Proxy proxy, LidoARM newImpl) = _deployInitializedLidoARMProxy();
        bytes memory data = script.migrateLegacyWithdrawQueueData();
        vm.store(address(proxy), bytes32(LIDO_LEGACY_WITHDRAWAL_QUEUE_AMOUNT_SLOT), bytes32(uint256(1 ether)));

        vm.expectRevert();
        proxy.upgradeToAndCall(address(newImpl), data);
    }

    function test_RevertWhen_MigrateLegacyWithdrawQueue_LegacyLidoWithdrawalRequestsPending() external {
        (Proxy proxy, LidoARM newImpl) = _deployInitializedLidoARMProxy();
        proxy.upgradeTo(address(newImpl));
        vm.store(address(proxy), bytes32(LIDO_LEGACY_WITHDRAWAL_QUEUE_AMOUNT_SLOT), bytes32(uint256(1 ether)));

        vm.expectRevert(LidoARM.LegacyLidoWithdrawalsPending.selector);
        LidoARM(payable(address(proxy))).migrateLegacyWithdrawQueue();
    }

    function test_UpgradeToAndCallMigratesWithPendingLegacyWithdrawQueue() external {
        (Proxy proxy, LidoARM newImpl) = _deployInitializedLidoARMProxy();
        bytes memory data = script.migrateLegacyWithdrawQueueData();
        uint256 packedLegacyQueue = _packLegacyWithdrawQueue(1 ether, 0);
        vm.store(address(proxy), bytes32(LEGACY_PACKED_WITHDRAW_QUEUE_SLOT), bytes32(packedLegacyQueue));
        vm.store(address(proxy), bytes32(NEXT_WITHDRAWAL_INDEX_SLOT), bytes32(uint256(3)));

        proxy.upgradeToAndCall(address(newImpl), data);

        assertEq(LidoARM(payable(address(proxy))).reservedWithdrawLiquidity(), 0);
        assertEq(LidoARM(payable(address(proxy))).legacyWithdrawalRequestCount(), 3);
        assertEq(uint256(vm.load(address(proxy), bytes32(LEGACY_PACKED_WITHDRAW_QUEUE_SLOT))), packedLegacyQueue);
    }

    function test_RevertWhen_MigrateLegacyWithdrawQueue_CalledTwice() external {
        (Proxy proxy, LidoARM newImpl) = _deployInitializedLidoARMProxy();

        proxy.upgradeToAndCall(address(newImpl), script.migrateLegacyWithdrawQueueData());

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        LidoARM(payable(address(proxy))).migrateLegacyWithdrawQueue();
    }

    function test_RevertWhen_MigrateLegacyWithdrawQueue_CalledByNonOwner() external {
        (Proxy proxy, LidoARM newImpl) = _deployInitializedLidoARMProxy();
        proxy.upgradeTo(address(newImpl));

        vm.prank(makeAddr("not owner"));
        vm.expectRevert(bytes4(keccak256("OnlyOwner()")));
        LidoARM(payable(address(proxy))).migrateLegacyWithdrawQueue();
    }

    function _packLegacyWithdrawQueue(uint128 queued, uint128 claimed) internal pure returns (uint256) {
        return uint256(queued) | (uint256(claimed) << 128);
    }

    function _deployInitializedLidoARMProxy() internal returns (Proxy proxy, LidoARM newImpl) {
        MockERC20 weth = new MockERC20("Wrapped ETH", "WETH", 18);

        LidoARM oldImpl = new LidoARM(address(weth), 10 minutes, 0, 0);
        newImpl = new LidoARM(address(weth), 10 minutes, 0, 0);
        proxy = new Proxy();

        weth.mint(address(this), 1e12);
        weth.approve(address(proxy), 1e12);

        bytes memory data = abi.encodeWithSelector(
            LidoARM.initialize.selector, "Lido ARM", "ARM-WETH-stETH", address(this), 2000, address(this), address(0)
        );
        proxy.initialize(address(oldImpl), address(this), data);
    }
}
