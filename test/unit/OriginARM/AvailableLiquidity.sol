// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "contracts/Interfaces.sol";
import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";

contract Unit_Concrete_OriginARM_AvailableLiquidity_Test_ is Unit_Shared_Test {
    function setUp() public virtual override {
        super.setUp();

        // Give Alice some WETH
        deal(address(weth), alice, 1_000 * DEFAULT_AMOUNT);

        // Alice approve max WETH to the ARM
        vm.prank(alice);
        weth.approve(address(originARM), type(uint256).max);
    }

    function test_AvailableLiquidity_AfterDeposit() public deposit(alice, DEFAULT_AMOUNT) {
        assertEq(originARM.availableLiquidity(weth), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY);
        assertEq(originARM.availableLiquidity(oeth), 0);
    }

    function test_AvailableLiquidity_AfterDepositAndSwap() public deposit(alice, DEFAULT_AMOUNT) swapAllWETHForOETH {
        assertEq(originARM.availableLiquidity(weth), 0);
        assertApproxEqRel(originARM.availableLiquidity(oeth), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1e16);
    }

    function test_AvailableLiquidity_AfterDepositSwapRequest()
        public
        deposit(alice, DEFAULT_AMOUNT)
        swapWETHForOETH(DEFAULT_AMOUNT / 2)
        requestRedeemAll(alice)
    {
        assertApproxEqRel(weth.balanceOf(address(originARM)), DEFAULT_AMOUNT / 2, 1e16);
        assertApproxEqRel(originARM.availableLiquidity(oeth), DEFAULT_AMOUNT / 2, 1e16); //
        assertEq(originARM.availableLiquidity(weth), 0); // Because outstanding withdraw are 1 ether
    }

    function test_AvailableLiquidity_WrongToken() public view {
        assertEq(originARM.availableLiquidity(IERC20(address(0))), 0);
    }
}
