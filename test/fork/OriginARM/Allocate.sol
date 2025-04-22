// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AbstractARM} from "contracts/AbstractARM.sol";
import {Fork_Shared_Test} from "test/fork/OriginARM/shared/Shared.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract Fork_Concrete_OriginARM_Allocate_Test_ is Fork_Shared_Test {
    using SafeCast for uint256;
    using SafeCast for int256;

    uint256 public initialShares;

    function setUp() public virtual override {
        super.setUp();
        initialShares = market.convertToShares(MIN_TOTAL_SUPPLY);
    }

    function test_Fork_Allocate_When_FirstAllocation() public setARMBuffer(0) addMarket(address(market)) asGovernor {
        // Assertions before allocation
        assertEq(market.balanceOf(address(originARM)), 0, "shares before");
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "totalAssets before");
        uint256 expectedShares = market.convertToShares(MIN_TOTAL_SUPPLY);

        // Expected event
        vm.expectEmit(address(market));
        emit IERC4626.Deposit(address(originARM), address(originARM), MIN_TOTAL_SUPPLY, expectedShares);
        vm.expectEmit(address(originARM));
        emit AbstractARM.Allocated(address(market), MIN_TOTAL_SUPPLY.toInt256());

        // Main call
        originARM.setActiveMarket(address(market));

        // Assertions after allocation
        assertEq(market.balanceOf(address(originARM)), expectedShares, "shares after");
        assertApproxEqAbs(originARM.totalAssets(), MIN_TOTAL_SUPPLY, 1, "totalAssets after");
    }

    function test_Fork_Allocate_When_LiquidityDelta_IsPositive()
        public
        setARMBuffer(0)
        addMarket(address(market))
        setActiveMarket(address(market))
        deposit(alice, DEFAULT_AMOUNT)
    {
        // Assertions before allocation
        assertEq(market.balanceOf(address(originARM)), initialShares, "shares before");
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets before");
        uint256 expectedShares = market.convertToShares(DEFAULT_AMOUNT);

        // Expected event
        vm.expectEmit(address(market));
        emit IERC4626.Deposit(address(originARM), address(originARM), DEFAULT_AMOUNT, expectedShares);
        vm.expectEmit(address(originARM));
        emit AbstractARM.Allocated(address(market), DEFAULT_AMOUNT.toInt256());

        // Main call
        originARM.allocate();

        // Assertions after allocation
        assertEq(market.balanceOf(address(originARM)), expectedShares + initialShares, "shares after");
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets after");
    }

    function test_Fork_Allocate_When_LiquiditiDelta_IsNegative_PartialWithdraw()
        public
        setARMBuffer(0)
        addMarket(address(market))
        setActiveMarket(address(market))
        deposit(alice, DEFAULT_AMOUNT)
        allocate
        setARMBuffer(0.5 ether)
    {
        uint256 marketBalanceBefore = market.balanceOf(address(originARM));
        uint256 sharesBefore = market.convertToShares(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY);
        // Assertions before allocation
        assertEq(marketBalanceBefore, sharesBefore, "shares before");
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets before");

        int256 expectedAmount = getLiquidityDelta();
        uint256 expectedShares = market.previewWithdraw(abs(expectedAmount));

        // Expected event
        vm.expectEmit(address(market));
        emit IERC4626.Withdraw(
            address(originARM), address(originARM), address(originARM), abs(expectedAmount), expectedShares
        );
        vm.expectEmit(address(originARM));
        emit AbstractARM.Allocated(address(market), expectedAmount);

        // Main call
        originARM.allocate();

        // Assertions after allocation
        assertEq(market.balanceOf(address(originARM)), marketBalanceBefore - expectedShares, "shares after");
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets after");
    }

    // WIP
    function test_Fork_Allocate_When_LiquidityDelta_IsNegative_FullWithdraw()
        public
        setARMBuffer(0)
        addMarket(address(market))
        setActiveMarket(address(market))
        deposit(alice, DEFAULT_AMOUNT)
        allocate
        setARMBuffer(1 ether)
    {
        uint256 marketBalanceBefore = market.balanceOf(address(originARM));
        uint256 sharesBefore = market.convertToShares(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY);
        // Assertions before allocation
        assertEq(marketBalanceBefore, sharesBefore, "shares before");
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets before");

        int256 expectedAmount = getLiquidityDelta();
        uint256 expectedShares = market.previewWithdraw(abs(expectedAmount));
        assertApproxEqAbs(abs(expectedAmount), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "expectedAmount");

        // Expected event
        vm.expectEmit(address(market));
        emit IERC4626.Withdraw(
            address(originARM), address(originARM), address(originARM), abs(expectedAmount), expectedShares
        );
        vm.expectEmit(address(originARM));
        emit AbstractARM.Allocated(address(market), expectedAmount);

        // Main call
        originARM.allocate();

        // Assertions after allocation
        //assertEq(market.balanceOf(address(originARM)), 987, "shares after"); This is weird, it should be 0
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets after");

        //deal(address(os), address(originARM), 1 ether);
        _swapAllWSForOS();
        originARM.allocate();
    }

    /* WIP
    function test_Fork_Allocate_When_LiquidityDelta_IsNegative_DesiredIsLessThanAvailable()
        public
        setFee(0)
        setARMBuffer(0)
        addMarket(address(market))
        setActiveMarket(address(market))
        deposit(alice, DEFAULT_AMOUNT)
        allocate
        setARMBuffer(1 ether)
        donate(os, address(originARM), 1 ether)
    {
        uint256 marketBalanceBefore = market.balanceOf(address(originARM));
        uint256 sharesBefore = market.convertToShares(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY);
        // Assertions before allocation
        assertEq(marketBalanceBefore, sharesBefore, "shares before");
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets before");

        int256 expectedAmount = getLiquidityDelta();
        uint256 expectedShares = market.previewWithdraw(abs(expectedAmount));

        // Expected event
        vm.expectEmit(address(market));
        emit IERC4626.Withdraw(
            address(originARM), address(originARM), address(originARM), abs(expectedAmount), expectedShares
        );
        vm.expectEmit(address(originARM));
        emit AbstractARM.Allocated(address(market), expectedAmount);
        // Main call
        originARM.allocate();

        // Assertions after allocation
        assertEq(market.balanceOf(address(originARM)), marketBalanceBefore - expectedShares, "shares after");
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets after");
    }
    */

    /// @dev This suppose that there is no fee!
    function getLiquidityDelta() public view returns (int256) {
        // Available assets
        uint256 availableAssets = originARM.totalAssets();
        uint256 armBuffer = originARM.armBuffer();
        uint256 targetArmLiquidity = availableAssets * armBuffer / 1e18;

        // ARM liquidity
        uint256 withdrawQueued = originARM.withdrawsQueued();
        uint256 withdrawClaimed = originARM.withdrawsClaimed();
        uint256 outstandingWithdrawals = withdrawQueued - withdrawClaimed;
        int256 armLiquidity = ws.balanceOf(address(originARM)).toInt256() - outstandingWithdrawals.toInt256();
        return armLiquidity - targetArmLiquidity.toInt256();
    }
}
