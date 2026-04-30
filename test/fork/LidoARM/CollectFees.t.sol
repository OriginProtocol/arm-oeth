// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";

contract Fork_Concrete_LidoARM_AccrueSwapFee_Test_ is Fork_Shared_Test_ {
    uint256 internal constant DISCOUNTED_PRICE = 9995e32; // 0.9995

    function setUp() public override {
        super.setUp();
    }

    /// @dev Performs a discounted base-asset (stETH) buy swap. Under the new model
    /// the fee is taken in stETH directly from `amountIn` and transferred to `feeCollector`
    /// during the swap. Returns the swap output and the expected fee in stETH.
    function _swapBaseForLiquidity(uint256 wethBalance, uint256 amountIn)
        internal
        returns (uint256 amountOut, uint256 expectedFee)
    {
        lidoARM.setPrices(DISCOUNTED_PRICE, 1001e33, type(uint256).max, type(uint256).max);
        deal(address(weth), address(lidoARM), wethBalance);
        deal(address(steth), address(this), amountIn);
        steth.approve(address(lidoARM), type(uint256).max);

        expectedFee = amountIn * lidoARM.fee() / lidoARM.FEE_SCALE();

        uint256[] memory amounts = lidoARM.swapExactTokensForTokens(steth, weth, amountIn, 0, address(this));
        amountOut = amounts[1];
    }

    function test_AccrueSwapFee_Once() public {
        address feeCollector = lidoARM.feeCollector();
        uint256 stethBefore = steth.balanceOf(feeCollector);

        (, uint256 expectedFee) = _swapBaseForLiquidity(200 ether, 100 ether);

        assertGt(expectedFee, 0, "non-zero fee");
        assertApproxEqAbs(
            steth.balanceOf(feeCollector) - stethBefore,
            expectedFee,
            STETH_ERROR_ROUNDING,
            "fee transferred to feeCollector in stETH"
        );
    }

    function test_AccrueSwapFee_Twice() public {
        address feeCollector = lidoARM.feeCollector();
        uint256 stethBefore = steth.balanceOf(feeCollector);

        (, uint256 fee1) = _swapBaseForLiquidity(200 ether, 100 ether);
        (, uint256 fee2) = _swapBaseForLiquidity(200 ether, 100 ether);

        assertApproxEqAbs(
            steth.balanceOf(feeCollector) - stethBefore,
            fee1 + fee2,
            2 * STETH_ERROR_ROUNDING,
            "fees accumulate at feeCollector across swaps"
        );
    }

    /// @notice No fee is charged when the ARM sells the base asset (trader buys stETH with WETH).
    function test_AccrueSwapFee_NotCharged_When_SellingBaseAsset() public {
        lidoARM.setPrices(0.99e36, 1e36, type(uint256).max, type(uint256).max);

        deal(address(steth), address(lidoARM), 100 ether);
        deal(address(weth), address(this), 100 ether);
        weth.approve(address(lidoARM), type(uint256).max);

        address feeCollector = lidoARM.feeCollector();
        uint256 stethBefore = steth.balanceOf(feeCollector);
        uint256 wethBefore = weth.balanceOf(feeCollector);

        lidoARM.swapExactTokensForTokens(weth, steth, 1 ether, 0, address(this));

        assertEq(steth.balanceOf(feeCollector), stethBefore, "no stETH fee");
        assertEq(weth.balanceOf(feeCollector), wethBefore, "no WETH fee");
    }
}
