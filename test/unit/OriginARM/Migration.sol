// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";

contract Unit_Concrete_OriginARM_Migration_Test is Unit_Shared_Test {
    function test_MigrateFeesAccrued_ClearsLegacyBitsAndPreservesFee() public {
        uint256 originalFee = originARM.fee();
        uint128 legacyValue = 123_456_789;

        vm.store(address(originARM), bytes32(_FEE_STORAGE_SLOT), bytes32((uint256(legacyValue) << 16) | originalFee));

        assertEq(originARM.feesAccrued(), legacyValue, "legacy bits should be visible before migration");
        assertEq(originARM.fee(), originalFee, "fee should remain readable before migration");

        vm.prank(governor);
        originARM.migrateFeesAccrued();

        assertEq(originARM.feesAccrued(), 1, "feesAccrued sentinel should be reset");
        assertEq(originARM.fee(), originalFee, "fee should be preserved");
    }

    function test_RevertWhen_MigrateFeesAccrued_CalledTwice() public {
        vm.prank(governor);
        originARM.migrateFeesAccrued();

        vm.prank(governor);
        vm.expectRevert();
        originARM.migrateFeesAccrued();
    }
}
