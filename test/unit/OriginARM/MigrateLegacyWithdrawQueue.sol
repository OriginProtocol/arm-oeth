// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";

contract Unit_Concrete_OriginARM_MigrateLegacyWithdrawQueue_Test_ is Unit_Shared_Test {
    using stdStorage for StdStorage;

    function test_RevertWhen_MigrateLegacyWithdrawQueue_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert(bytes4(keccak256("OnlyOwner()")));
        originARM.migrateLegacyWithdrawQueue();
    }

    function test_MigrateLegacyWithdrawQueue_When_LegacyQueueIsZero() public asGovernor {
        originARM.migrateLegacyWithdrawQueue();

        assertEq(originARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
    }

    function test_MigrateLegacyWithdrawQueue_When_LegacyQueueIsFullyClaimed() public asGovernor {
        uint128 legacyQueued = 5 ether;
        uint128 legacyClaimed = legacyQueued;
        _writeLegacyWithdrawQueue(legacyQueued, legacyClaimed);

        originARM.migrateLegacyWithdrawQueue();

        assertEq(originARM.reservedWithdrawLiquidity(), 0, "reserved liquidity");
    }

    function test_RevertWhen_MigrateLegacyWithdrawQueue_Because_LegacyWithdrawalsPending() public asGovernor {
        _writeLegacyWithdrawQueue(5 ether, 4 ether);

        vm.expectRevert(bytes4(keccak256("LegacyWithdrawalsPending()")));
        originARM.migrateLegacyWithdrawQueue();
    }

    function test_RevertWhen_MigrateLegacyWithdrawQueue_Because_LegacyOriginWithdrawalsPending() public asGovernor {
        stdstore.target(address(originARM)).sig(originARM.vaultWithdrawalAmount.selector).checked_write(uint256(1 ether));

        vm.expectRevert(OriginARM.LegacyOriginWithdrawalsPending.selector);
        originARM.migrateLegacyWithdrawQueue();
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
        uint256 packedLegacyQueue = uint256(legacyQueued) | (uint256(legacyClaimed) << 128);

        stdstore.target(address(originARM)).sig(originARM.reservedWithdrawLiquidity.selector)
            .checked_write(packedLegacyQueue);

        assertEq(originARM.reservedWithdrawLiquidity(), packedLegacyQueue, "packed legacy queue");
    }
}
