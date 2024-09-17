// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {IERC20} from "contracts/Interfaces.sol";
import {LidoMultiPriceMultiLpARM} from "contracts/LidoMultiPriceMultiLpARM.sol";
import {Proxy} from "contracts/Proxy.sol";

import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

contract Fork_Concrete_LidoMultiPriceMultiLpARM_Test is Fork_Shared_Test_ {
    Proxy public lidoProxy;
    LidoMultiPriceMultiLpARM public lidoARM;
    IERC20 BAD_TOKEN = IERC20(makeAddr("bad token"));
    uint256 performanceFee = 2000; // 20%
    address feeCollector = 0x000000000000000000000000000000Feec011ec1;

    // Account for stETH rounding errors.
    // See https://docs.lido.fi/guides/lido-tokens-integration-guide/#1-2-wei-corner-case
    uint256 constant ROUNDING = 2;

    function setUp() public override {
        super.setUp();

        address lidoWithdrawal = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
        LidoMultiPriceMultiLpARM lidoImpl = new LidoMultiPriceMultiLpARM(address(steth), address(weth), lidoWithdrawal);
        lidoProxy = new Proxy();

        // The deployer needs a tiny amount of WETH to initialize the ARM
        _dealWETH(address(this), 1e12);
        weth.approve(address(lidoProxy), type(uint256).max);
        steth.approve(address(lidoProxy), type(uint256).max);

        // Initialize Proxy with LidoMultiPriceMultiLpARM implementation.
        bytes memory data = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address)",
            "Lido ARM",
            "ARM-ST",
            operator,
            performanceFee,
            feeCollector
        );
        lidoProxy.initialize(address(lidoImpl), address(this), data);

        lidoARM = LidoMultiPriceMultiLpARM(payable(address(lidoProxy)));

        // Set the tranche discounts for each tranche
        // 8 basis point discount (0.08%) would be 800 with a price of 0.9992
        lidoARM.setTrancheDiscounts([uint16(200), 375, 800, 1400, 1800]);
        lidoARM.setTrancheAllocations([uint256(80 ether), 50 ether, 30 ether, 20 ether, 10 ether]);

        lidoARM.setTotalAssetsCap(100 ether);

        // Only fuzz from this address. Big speedup on fork.
        targetSender(address(this));
    }

    function _dealStETH(address to, uint256 amount) internal {
        vm.prank(0xEB9c1CE881F0bDB25EAc4D74FccbAcF4Dd81020a);
        steth.transfer(to, amount);
    }

    function _dealWETH(address to, uint256 amount) internal {
        deal(address(weth), to, amount);
    }

    /// @dev Check initial state
    function test_initial_state() external {
        assertEq(lidoARM.name(), "Lido ARM");
        assertEq(lidoARM.symbol(), "ARM-ST");
        assertEq(lidoARM.owner(), address(this));
        assertEq(lidoARM.operator(), operator);
        assertEq(lidoARM.feeCollector(), feeCollector);
        assertEq(lidoARM.fee(), performanceFee);
        assertEq(lidoARM.lastTotalAssets(), 0);
        assertEq(lidoARM.feesAccrued(), 0);
        // the 20% performance fee is removed
        assertEq(lidoARM.totalAssets(), 1e12 * 0.8);
        assertEq(lidoARM.totalSupply(), 1e12);
        assertEq(weth.balanceOf(address(lidoARM)), 1e12);
        assertEq(lidoARM.totalAssetsCap(), 100 ether);
    }

    /// @dev ARM owner sets valid trance discounts ranging from 1 to MAX_DISCOUNT
    function test_setValidTrancheDiscounts() external {
        lidoARM.setTrancheDiscounts([uint16(1), 20, 300, 9999, 65535]);
        uint16[5] memory discounts = lidoARM.getTrancheDiscounts();
        assertEq(discounts[0], 1);
        assertEq(discounts[1], 20);
        assertEq(discounts[2], 300);
        assertEq(discounts[3], 9999);
        assertEq(discounts[4], 65535);
    }
    // Revert when a tranche discount is zero
    // Revert when a tranche discount is greater than the MAX_DISCOUNT
    // Revert when non owner tries to set tranche discounts

    // whitelisted LP adds WETH liquidity to the ARM
    function test_depositAssets() external {
        lidoARM.setLiquidityProviderCap(address(this), 20 ether);

        _dealWETH(address(this), 10 ether);
        uint256 startWETH = weth.balanceOf(address(lidoARM));

        lidoARM.deposit(10 ether);

        assertEq(weth.balanceOf(address(lidoARM)), startWETH + 10 ether);
    }
    // non whitelisted LP tries to add WETH liquidity to the ARM

    function test_redeemAssets() external {
        lidoARM.setLiquidityProviderCap(address(this), 20 ether);
        _dealWETH(address(this), 10 ether);
        lidoARM.deposit(10 ether);

        lidoARM.requestRedeem(8 ether);
    }

    // with enough liquidity in all tranches
    //// swap stETH to WETH using just the first tranche
    //// swap stETH to WETH using the first two tranches
    //// swap stETH to WETH using all five tranches
    //// fail to swap stETH to WETH with a swap larger than the available liquidity
    // with all liquidity in the first tranche used
    //// swap stETH to WETH using just the second tranche
    //// swap stETH to WETH using the second and third tranches
    //// swap stETH to WETH using the remaining four tranches
    //// fail to swap stETH to WETH with a swap larger than the available liquidity
    // with only liquidity in the fifth tranche
    //// swap stETH to WETH using just the fifth tranche

    // function test_realistic_swaps() external {
    //     // vm.prank(operator);
    //     // lidoARM.setPrices(997 * 1e33, 998 * 1e33);
    //     _swapExactTokensForTokens(steth, weth, 10 ether, 9.97 ether);
    //     // _swapExactTokensForTokens(weth, steth, 10 ether, 10020040080160320641);
    // }

    // function test_swapExactTokensForTokens_WETH_TO_STETH() external {
    //     _swapExactTokensForTokens(weth, steth, 10 ether, 6.25 ether);
    // }

    // function test_swapExactTokensForTokens_STETH_TO_WETH() external {
    //     _swapExactTokensForTokens(steth, weth, 10 ether, 5 ether);
    // }

    // function test_swapTokensForExactTokens_WETH_TO_STETH() external {
    //     _swapTokensForExactTokens(weth, steth, 10 ether, 6.25 ether);
    // }

    // function test_swapTokensForExactTokens_STETH_TO_WETH() external {
    //     _swapTokensForExactTokens(steth, weth, 10 ether, 5 ether);
    // }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, uint256 expectedOut)
        internal
    {
        if (inToken == weth) {
            _dealWETH(address(this), amountIn + 1000);
        } else {
            _dealStETH(address(this), amountIn + 1000);
        }
        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));
        lidoARM.swapExactTokensForTokens(inToken, outToken, amountIn, 0, address(this));
        assertGt(inToken.balanceOf(address(this)), (startIn - amountIn) - ROUNDING, "In actual");
        assertLt(inToken.balanceOf(address(this)), (startIn - amountIn) + ROUNDING, "In actual");
        assertGe(outToken.balanceOf(address(this)), startOut + expectedOut - ROUNDING, "Out actual");
        assertLe(outToken.balanceOf(address(this)), startOut + expectedOut + ROUNDING, "Out actual");
    }

    // function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, uint256 expectedOut)
    //     internal
    // {
    //     if (inToken == weth) {
    //         _dealWETH(address(this), amountIn + 1000);
    //     } else {
    //         _dealStETH(address(this), amountIn + 1000);
    //     }
    //     uint256 startIn = inToken.balanceOf(address(this));
    //     lidoARM.swapTokensForExactTokens(inToken, outToken, expectedOut, 3 * expectedOut, address(this));
    //     assertGt(inToken.balanceOf(address(this)), (startIn - amountIn) - ROUNDING, "In actual");
    //     assertLt(inToken.balanceOf(address(this)), (startIn - amountIn) + ROUNDING, "In actual");
    //     assertGe(outToken.balanceOf(address(this)), expectedOut - ROUNDING, "Out actual");
    //     assertLe(outToken.balanceOf(address(this)), expectedOut + ROUNDING, "Out actual");
    // }

    // function test_unauthorizedAccess() external {
    //     address RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;
    //     vm.startPrank(RANDOM_ADDRESS);

    //     // Proxy's restricted methods.
    //     vm.expectRevert("ARM: Only owner can call this function.");
    //     proxy.setOwner(RANDOM_ADDRESS);

    //     vm.expectRevert("ARM: Only owner can call this function.");
    //     proxy.initialize(address(this), address(this), "");

    //     vm.expectRevert("ARM: Only owner can call this function.");
    //     proxy.upgradeTo(address(this));

    //     vm.expectRevert("ARM: Only owner can call this function.");
    //     proxy.upgradeToAndCall(address(this), "");

    //     // Implementation's restricted methods.
    //     vm.expectRevert("ARM: Only owner can call this function.");
    //     lidoARM.setOwner(RANDOM_ADDRESS);

    //     vm.expectRevert("ARM: Only operator or owner can call this function.");
    //     lidoARM.setPrices(123, 321);
    // }

    // function test_wrongInTokenExactIn() external {
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapExactTokensForTokens(BAD_TOKEN, steth, 10 ether, 0, address(this));
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapExactTokensForTokens(BAD_TOKEN, weth, 10 ether, 0, address(this));
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapExactTokensForTokens(weth, weth, 10 ether, 0, address(this));
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapExactTokensForTokens(steth, steth, 10 ether, 0, address(this));
    // }

    // function test_wrongOutTokenExactIn() external {
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapTokensForExactTokens(weth, BAD_TOKEN, 10 ether, 0, address(this));
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapTokensForExactTokens(steth, BAD_TOKEN, 10 ether, 0, address(this));
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapTokensForExactTokens(weth, weth, 10 ether, 0, address(this));
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapTokensForExactTokens(steth, steth, 10 ether, 0, address(this));
    // }

    // function test_wrongInTokenExactOut() external {
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapTokensForExactTokens(BAD_TOKEN, steth, 10 ether, 0, address(this));
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapTokensForExactTokens(BAD_TOKEN, weth, 10 ether, 0, address(this));
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapTokensForExactTokens(weth, weth, 10 ether, 0, address(this));
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapTokensForExactTokens(steth, steth, 10 ether, 0, address(this));
    // }

    // function test_wrongOutTokenExactOut() external {
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapTokensForExactTokens(weth, BAD_TOKEN, 10 ether, 0, address(this));
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapTokensForExactTokens(steth, BAD_TOKEN, 10 ether, 0, address(this));
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapTokensForExactTokens(weth, weth, 10 ether, 0, address(this));
    //     vm.expectRevert("ARM: Invalid token");
    //     lidoARM.swapTokensForExactTokens(steth, steth, 10 ether, 0, address(this));
    // }

    // function test_collectTokens() external {
    //     lidoARM.transferToken(address(weth), address(this), weth.balanceOf(address(lidoARM)));
    //     assertGt(weth.balanceOf(address(this)), 50 ether);
    //     assertEq(weth.balanceOf(address(lidoARM)), 0);

    //     lidoARM.transferToken(address(steth), address(this), steth.balanceOf(address(lidoARM)));
    //     assertGt(steth.balanceOf(address(this)), 50 ether);
    //     assertLt(steth.balanceOf(address(lidoARM)), 3);
    // }

    // /* Operator Tests */

    // function test_setOperator() external {
    //     lidoARM.setOperator(address(this));
    //     assertEq(lidoARM.operator(), address(this));
    // }

    // function test_nonOwnerCannotSetOperator() external {
    //     vm.expectRevert("ARM: Only owner can call this function.");
    //     vm.prank(operator);
    //     lidoARM.setOperator(operator);
    // }

    // function test_setMinimumFunds() external {
    //     lidoARM.setMinimumFunds(100 ether);
    //     assertEq(lidoARM.minimumFunds(), 100 ether);
    // }

    // function test_setGoodCheckedTraderates() external {
    //     vm.prank(operator);
    //     lidoARM.setPrices(992 * 1e33, 2000 * 1e33);
    //     assertEq(lidoARM.traderate0(), 500 * 1e33);
    //     assertEq(lidoARM.traderate1(), 992 * 1e33);
    // }

    // function test_setBadCheckedTraderates() external {
    //     vm.prank(operator);
    //     vm.expectRevert("ARM: Traderate too high");
    //     lidoARM.setPrices(1010 * 1e33, 1020 * 1e33);
    //     vm.prank(operator);
    //     vm.expectRevert("ARM: Traderate too high");
    //     lidoARM.setPrices(993 * 1e33, 994 * 1e33);
    // }

    // function test_checkTraderateFailsMinimumFunds() external {
    //     uint256 currentFunds =
    //         lidoARM.token0().balanceOf(address(lidoARM)) + lidoARM.token1().balanceOf(address(lidoARM));
    //     lidoARM.setMinimumFunds(currentFunds + 100);

    //     vm.prank(operator);
    //     vm.expectRevert("ARM: Too much loss");
    //     lidoARM.setPrices(992 * 1e33, 1001 * 1e33);
    // }

    // function test_checkTraderateWorksMinimumFunds() external {
    //     uint256 currentFunds =
    //         lidoARM.token0().balanceOf(address(lidoARM)) + lidoARM.token1().balanceOf(address(lidoARM));
    //     lidoARM.setMinimumFunds(currentFunds - 100);

    //     vm.prank(operator);
    //     lidoARM.setPrices(992 * 1e33, 1001 * 1e33);
    // }

    // // Slow on fork
    // function invariant_nocrossed_trading_exact_eth() external {
    //     uint256 sumBefore = weth.balanceOf(address(lidoARM)) + steth.balanceOf(address(lidoARM));
    //     _dealWETH(address(this), 1 ether);
    //     lidoARM.swapExactTokensForTokens(weth, steth, weth.balanceOf(address(lidoARM)), 0, address(this));
    //     lidoARM.swapExactTokensForTokens(steth, weth, steth.balanceOf(address(lidoARM)), 0, address(this));
    //     uint256 sumAfter = weth.balanceOf(address(lidoARM)) + steth.balanceOf(address(lidoARM));
    //     assertGt(sumBefore, sumAfter, "Lost money swapping");
    // }
}
