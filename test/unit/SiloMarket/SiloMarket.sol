// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {SiloMarket} from "contracts/markets/SiloMarket.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract Unit_Concrete_OriginARM_SiloMarket_Test_ is Unit_Shared_Test {
    function setUp() public virtual override {
        super.setUp();

        vm.mockCall(address(market), abi.encodeWithSelector(IERC4626.maxWithdraw.selector), abi.encode(1));
        vm.mockCall(address(market), abi.encodeWithSelector(IERC4626.maxRedeem.selector), abi.encode(1));
    }
    ////////////////////////////////////////////////////
    /// --- REVERT
    ////////////////////////////////////////////////////

    function test_RevertWhen_Deposit_Because_OnlyARMCanDeposit() public asNot(address(originARM)) {
        vm.expectRevert("Only ARM can deposit");
        siloMarket.deposit(0, address(originARM));

        vm.stopPrank();
        vm.prank(address(originARM));
        vm.expectRevert("Only ARM can deposit");
        siloMarket.deposit(0, address(this));
    }

    function test_RevertWhen_Withdraw_Because_OnlyARMCanWithdraw() public asNot(address(originARM)) {
        vm.expectRevert("Only ARM can withdraw");
        siloMarket.withdraw(0, address(originARM), address(originARM));

        vm.stopPrank();
        vm.prank(address(originARM));
        vm.expectRevert("Only ARM can withdraw");
        siloMarket.withdraw(0, address(this), address(originARM));

        vm.prank(address(originARM));
        vm.expectRevert("Only ARM can withdraw");
        siloMarket.withdraw(0, address(originARM), address(this));
    }

    function test_RevertWhen_Redeem_Because_OnlyARMCanWithdraw() public asNot(address(originARM)) {
        vm.expectRevert("Only ARM can redeem");
        siloMarket.redeem(0, address(originARM), address(originARM));

        vm.stopPrank();
        vm.prank(address(originARM));
        vm.expectRevert("Only ARM can redeem");
        siloMarket.redeem(0, address(this), address(originARM));

        vm.prank(address(originARM));
        vm.expectRevert("Only ARM can redeem");
        siloMarket.redeem(0, address(originARM), address(this));
    }

    function test_RevertWhen_SetHarvester_Because_OnlyOwner() public asNotGovernor {
        vm.expectRevert("ARM: Only owner can call this function.");
        siloMarket.setHarvester(address(this));
    }

    function test_RevertWhen_SetHarvester_Because_AlreadySet() public asGovernor {
        address currentHarvester = siloMarket.harvester();

        vm.expectRevert("Harvester already set");
        siloMarket.setHarvester(currentHarvester);
    }

    function test_RevertWhen_CollectRewardTokens_Because_OnlyHarvester() public asNotOperatorNorGovernor {
        vm.expectRevert("Only harvester can collect");
        siloMarket.collectRewards();
    }

    ////////////////////////////////////////////////////
    /// --- SETTERS
    ////////////////////////////////////////////////////
    function test_SetHarvester() public asGovernor {
        address newHarvester = randomAddrDiff(siloMarket.harvester());

        vm.expectEmit(address(siloMarket));
        emit SiloMarket.HarvesterUpdated(newHarvester);
        siloMarket.setHarvester(newHarvester);

        assertEq(siloMarket.harvester(), newHarvester, "harvester");
    }

    ////////////////////////////////////////////////////
    /// --- VIEWS
    ////////////////////////////////////////////////////
    function test_MaxWithdraw() public view {
        assertEq(siloMarket.maxWithdraw(address(originARM)), 1, "maxWithdraw");
        assertEq(siloMarket.maxWithdraw(address(this)), 0, "maxWithdraw");
    }

    function test_MaxRedeem() public view {
        assertEq(siloMarket.maxRedeem(address(originARM)), 1, "maxRedeem");
        assertEq(siloMarket.maxRedeem(address(this)), 0, "maxRedeem");
    }
}
