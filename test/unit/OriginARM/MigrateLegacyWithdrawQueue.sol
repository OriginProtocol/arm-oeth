// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";

contract Unit_Concrete_OriginARM_MigrateLegacyWithdrawQueue_Test_ is Unit_Shared_Test {
    uint256 internal constant LEGACY_PACKED_WITHDRAW_QUEUE_SLOT = 53;
    uint256 internal constant NEXT_WITHDRAWAL_INDEX_SLOT = 54;

    function test_RevertWhen_MigrateLegacyWithdrawQueue_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert(bytes4(keccak256("OnlyOwner()")));
        originARM.migrateLegacyWithdrawQueue();
    }

    function test_MigrateLegacyWithdrawQueue_When_LegacyQueueIsZero() public asGovernor {
        _writeNextWithdrawalIndex(3);

        originARM.migrateLegacyWithdrawQueue();

        assertEq(originARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
        assertEq(originARM.legacyWithdrawalRequestCount(), 3, "legacy request count");
    }

    function test_MigrateLegacyWithdrawQueue_When_LegacyQueueIsFullyClaimed() public asGovernor {
        uint128 legacyQueued = 5 ether;
        uint128 legacyClaimed = legacyQueued;
        _writeLegacyWithdrawQueue(legacyQueued, legacyClaimed);
        _writeNextWithdrawalIndex(3);

        originARM.migrateLegacyWithdrawQueue();

        assertEq(originARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
        assertEq(originARM.legacyWithdrawalRequestCount(), 3, "legacy request count");
        assertEq(
            _readLegacyWithdrawQueue(), _packLegacyWithdrawQueue(legacyQueued, legacyClaimed), "legacy queue preserved"
        );
    }

    function test_MigrateLegacyWithdrawQueue_When_LegacyWithdrawalsPending() public asGovernor {
        _writeLegacyWithdrawQueue(5 ether, 4 ether);
        _writeNextWithdrawalIndex(3);

        originARM.migrateLegacyWithdrawQueue();

        assertEq(originARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
        assertEq(originARM.legacyWithdrawalRequestCount(), 3, "legacy request count");
        assertEq(_readLegacyWithdrawQueue(), _packLegacyWithdrawQueue(5 ether, 4 ether), "legacy queue preserved");
    }

    function test_RevertWhen_MigrateLegacyWithdrawQueue_Because_NewQueueAlreadyUsed()
        public
        deposit(alice, DEFAULT_AMOUNT)
    {
        vm.prank(alice);
        originARM.requestRedeem(DEFAULT_AMOUNT);

        vm.prank(governor);
        vm.expectRevert(bytes4(keccak256("AlreadyMigrated()")));
        originARM.migrateLegacyWithdrawQueue();
    }

    function _writeLegacyWithdrawQueue(uint128 legacyQueued, uint128 legacyClaimed) internal {
        uint256 packedLegacyQueue = _packLegacyWithdrawQueue(legacyQueued, legacyClaimed);

        vm.store(address(originARM), bytes32(LEGACY_PACKED_WITHDRAW_QUEUE_SLOT), bytes32(packedLegacyQueue));
        assertEq(_readLegacyWithdrawQueue(), packedLegacyQueue, "packed legacy queue");
        assertEq(originARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
    }

    function _readLegacyWithdrawQueue() internal view returns (uint256) {
        return uint256(vm.load(address(originARM), bytes32(LEGACY_PACKED_WITHDRAW_QUEUE_SLOT)));
    }

    function _writeNextWithdrawalIndex(uint256 nextWithdrawalIndex) internal {
        vm.store(address(originARM), bytes32(NEXT_WITHDRAWAL_INDEX_SLOT), bytes32(nextWithdrawalIndex));
        assertEq(originARM.nextWithdrawalIndex(), nextWithdrawalIndex, "next withdrawal index");
    }

    function _packLegacyWithdrawQueue(uint128 legacyQueued, uint128 legacyClaimed) internal pure returns (uint256) {
        return uint256(legacyQueued) | (uint256(legacyClaimed) << 128);
    }
}
