// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";
import {MockMarketSwapTarget} from "test/unit/mocks/MockMarketSwapTarget.sol";

contract Fork_Concrete_LidoARM_MarketSwap_Test is Fork_Shared_Test_ {
    MockMarketSwapTarget internal target;

    function setUp() public override {
        super.setUp();
        target = new MockMarketSwapTarget();
    }

    function test_MarketSwap_StethOut_WethIn() public asOperator {
        uint256 amountOut = 1 ether;
        deal(address(steth), address(lidoARM), amountOut);
        deal(address(weth), address(target), amountOut);

        bytes memory data =
            abi.encodeWithSelector(MockMarketSwapTarget.executeSwap.selector, address(weth), address(lidoARM), amountOut);

        uint256 amountIn = lidoARM.marketSwap(weth, steth, amountOut, address(target), data);

        assertEq(amountIn, amountOut, "wrong amount in");
        assertEq(weth.balanceOf(address(lidoARM)), amountOut + 1e12, "wrong ARM WETH balance");
        assertEq(steth.balanceOf(address(target)), amountOut, "wrong target stETH balance");
    }
}
