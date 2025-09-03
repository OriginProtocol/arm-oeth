// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

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
        (uint256 balance0, uint256 balance1) = originARM.getReserves();
        assertEq(balance0, DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY);
        assertEq(balance1, 0);
    }

    function test_AvailableLiquidity_AfterDepositAndSwap() public deposit(alice, DEFAULT_AMOUNT) swapAllWETHForOETH {
        (uint256 balance0, uint256 balance1) = originARM.getReserves();
        assertEq(balance0, 0);
        assertApproxEqRel(balance1, DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1e16);
    }

    function test_AvailableLiquidity_AfterDepositSwapRequest()
        public
        deposit(alice, DEFAULT_AMOUNT)
        swapWETHForOETH(DEFAULT_AMOUNT / 2)
        requestRedeemAll(alice)
    {
        (uint256 balance0, uint256 balance1) = originARM.getReserves();
        assertApproxEqRel(weth.balanceOf(address(originARM)), DEFAULT_AMOUNT / 2, 1e16);
        assertApproxEqRel(balance1, DEFAULT_AMOUNT / 2, 1e16); //
        assertEq(balance0, 0); // Because outstanding withdraw are 1 ether
    }
}
