// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

contract Fork_Concrete_LidoARM_CollectFees_Test_ is Fork_Shared_Test_ {
    uint256 internal constant DISCOUNTED_PRICE = 9995e32; // 0.9995

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
    }

    function _swapBaseForLiquidity(uint256 wethBalance, uint256 amountIn)
        internal
        returns (uint256 amountOut, uint256 expectedFee)
    {
        lidoARM.setPrices(DISCOUNTED_PRICE, 1001e33);
        deal(address(weth), address(lidoARM), wethBalance);
        deal(address(steth), address(this), amountIn);
        steth.approve(address(lidoARM), type(uint256).max);

        uint256[] memory amounts = lidoARM.swapExactTokensForTokens(steth, weth, amountIn, 0, address(this));
        amountOut = amounts[1];
        expectedFee = (amountIn - amountOut) * lidoARM.fee() / lidoARM.FEE_SCALE();
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    /// @notice This test is expected to revert as the discounted swap leaves too little WETH to collect the accrued fee.
    function test_RevertWhen_CollectFees_Because_InsufficientLiquidity() public {
        _swapBaseForLiquidity(99_955e15, 100 ether);

        vm.expectRevert("ARM: insufficient liquidity");
        lidoARM.collectFees();
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_CollectFees_Once() public {
        address feeCollector = lidoARM.feeCollector();
        (, uint256 fee) = _swapBaseForLiquidity(200 ether, 100 ether);

        // Expected Events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(lidoARM), feeCollector, fee);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.FeeCollected(feeCollector, fee);

        // Main call
        uint256 claimedFee = lidoARM.collectFees();

        // Assertions after
        assertEq(claimedFee, fee);
        assertEq(lidoARM.feesAccrued(), 0);
    }

    function test_CollectFees_Twice() public {
        _swapBaseForLiquidity(200 ether, 100 ether);
        lidoARM.collectFees();
        (, uint256 expectedFee) = _swapBaseForLiquidity(200 ether, 100 ether);

        // Main call
        uint256 claimedFee = lidoARM.collectFees();

        // Assertions after
        assertEq(claimedFee, expectedFee);
    }
}
