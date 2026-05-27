// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {Ownable} from "contracts/Ownable.sol";
import {Unit_LidoARM_Shared_Test} from "../Shared.t.sol";

contract Unit_Concrete_LidoARM_MigrateLegacyWithdrawQueue_Test_ is Unit_LidoARM_Shared_Test {
    using stdStorage for StdStorage;

    uint256 internal constant LEGACY_PACKED_WITHDRAW_QUEUE_SLOT = 53;
    uint256 internal constant NEXT_WITHDRAWAL_INDEX_SLOT = 54;

    function test_RevertWhen_MigrateLegacyWithdrawQueue_Because_NotGovernor() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        lidoARM.migrateLegacyWithdrawQueue();
    }

    function test_MigrateLegacyWithdrawQueue_When_LegacyQueueIsZero() public {
        _writeNextWithdrawalIndex(3);

        vm.prank(governor);
        lidoARM.migrateLegacyWithdrawQueue();

        assertEq(lidoARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
        assertEq(lidoARM.legacyWithdrawalRequestCount(), 3, "legacy request count");
    }

    function test_MigrateLegacyWithdrawQueue_When_LegacyQueueIsFullyClaimed() public {
        uint128 legacyQueued = 5 ether;
        uint128 legacyClaimed = legacyQueued;
        _writeLegacyWithdrawQueue(legacyQueued, legacyClaimed);
        _writeNextWithdrawalIndex(3);

        vm.prank(governor);
        lidoARM.migrateLegacyWithdrawQueue();

        assertEq(lidoARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
        assertEq(lidoARM.legacyWithdrawalRequestCount(), 3, "legacy request count");
        assertEq(
            _readLegacyWithdrawQueue(), _packLegacyWithdrawQueue(legacyQueued, legacyClaimed), "legacy queue preserved"
        );
    }

    function test_MigrateLegacyWithdrawQueue_When_LegacyWithdrawalsPending() public {
        _writeLegacyWithdrawQueue(5 ether, 4 ether);
        _writeNextWithdrawalIndex(3);

        vm.prank(governor);
        lidoARM.migrateLegacyWithdrawQueue();

        assertEq(lidoARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
        assertEq(lidoARM.legacyWithdrawalRequestCount(), 3, "legacy request count");
        assertEq(_readLegacyWithdrawQueue(), _packLegacyWithdrawQueue(5 ether, 4 ether), "legacy queue preserved");
    }

    function test_RevertWhen_MigrateLegacyWithdrawQueue_Because_NewQueueAlreadyUsed() public {
        desactiveCapManager();
        aliceFirstDeposit(DEFAULT_AMOUNT);

        vm.prank(alice);
        lidoARM.requestRedeem(DEFAULT_AMOUNT);

        vm.prank(governor);
        vm.expectRevert(AbstractARM.AlreadyMigrated.selector);
        lidoARM.migrateLegacyWithdrawQueue();
    }

    function _writeLegacyWithdrawQueue(uint128 legacyQueued, uint128 legacyClaimed) internal {
        uint256 packedLegacyQueue = _packLegacyWithdrawQueue(legacyQueued, legacyClaimed);

        vm.store(address(lidoARM), bytes32(LEGACY_PACKED_WITHDRAW_QUEUE_SLOT), bytes32(packedLegacyQueue));
        assertEq(_readLegacyWithdrawQueue(), packedLegacyQueue, "packed legacy queue");
        assertEq(lidoARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
    }

    function _readLegacyWithdrawQueue() internal view returns (uint256) {
        return uint256(vm.load(address(lidoARM), bytes32(LEGACY_PACKED_WITHDRAW_QUEUE_SLOT)));
    }

    function _writeNextWithdrawalIndex(uint256 nextWithdrawalIndex) internal {
        vm.store(address(lidoARM), bytes32(NEXT_WITHDRAWAL_INDEX_SLOT), bytes32(nextWithdrawalIndex));
        assertEq(lidoARM.nextWithdrawalIndex(), nextWithdrawalIndex, "next withdrawal index");
    }

    function _packLegacyWithdrawQueue(uint128 legacyQueued, uint128 legacyClaimed) internal pure returns (uint256) {
        return uint256(legacyQueued) | (uint256(legacyClaimed) << 128);
    }
}
