// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract Unit_Concrete_OriginARM_ManageMarket_Test_ is Unit_Shared_Test {
    using SafeCast for int256;
    using SafeCast for int128;

    function setUp() public virtual override {
        super.setUp();

        // Give Alice some WETH
        deal(address(weth), alice, 1_000 * DEFAULT_AMOUNT);

        // Alice approve max WETH to the ARM
        vm.prank(alice);
        weth.approve(address(originARM), type(uint256).max);
    }

    function test_RevertWhen_AddMarket_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert("ARM: Only owner can call this function.");
        originARM.addMarket(address(0));
    }

    function test_RevertWhen_AddMarket_Because_AddressZero() public asGovernor {
        vm.expectRevert("ARM: invalid market");
        originARM.addMarket(address(0));
    }
}
