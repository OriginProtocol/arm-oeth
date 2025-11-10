// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Sonic} from "contracts/utils/Addresses.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {Fork_Shared_Test} from "test/fork/OriginARM/shared/Shared.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract Fork_Concrete_OriginARM_AllocateWithAdapter_Test_ is Fork_Shared_Test {
    using SafeCast for uint256;
    using SafeCast for int256;

    // There is a weird behavior from Silo siloMarket, where even when we remove all, we still have some shares left.
    uint256 public constant MIN_BALANCE = 1_000_000;

    uint256 public initialShares;

    function setUp() public virtual override {
        super.setUp();
        market = IERC4626(address(Sonic.SILO_VARLAMORE_S_VAULT));
        initialShares = market.convertToShares(MIN_TOTAL_SUPPLY);
    }

    function test_Fork_Allocate_When_FirstAllocation()
        public
        setARMBuffer(0)
        addMarket(address(siloMarket))
        asGovernor
    {
        // Assertions before allocation
        assertEq(market.balanceOf(address(siloMarket)), 0, "shares before");
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "totalAssets before");

        // Main call
        originARM.setActiveMarket(address(siloMarket));

        // Assertions after allocation
        assertEq(market.balanceOf(address(siloMarket)), 0, "shares after");
        assertApproxEqAbs(originARM.totalAssets(), MIN_TOTAL_SUPPLY, 1, "totalAssets after");
    }

    function test_Fork_Allocate_When_LiquidityDelta_IsPositive()
        public
        setARMBuffer(0)
        addMarket(address(siloMarket))
        setActiveMarket(address(siloMarket))
        deposit(alice, DEFAULT_AMOUNT)
    {
        // Assertions before allocation
        assertEq(market.balanceOf(address(siloMarket)), 0, "shares before");
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets before");
        uint256 expectedShares = market.convertToShares(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY);
        int256 expectedLiquidityDelta = (DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY).toInt256();

        // Expected event
        vm.expectEmit(address(market));
        emit IERC4626.Deposit(
            address(siloMarket), address(siloMarket), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, expectedShares
        );
        vm.expectEmit(address(originARM));
        emit AbstractARM.Allocated(address(siloMarket), expectedLiquidityDelta, expectedLiquidityDelta);

        // Main call
        originARM.allocate();

        // Assertions after allocation
        assertEq(market.balanceOf(address(siloMarket)), expectedShares, "shares after");
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets after");
    }

    function test_Fork_Allocate_When_LiquiditiDelta_IsNegative_PartialWithdraw()
        public
        setARMBuffer(0)
        addMarket(address(siloMarket))
        setActiveMarket(address(siloMarket))
        deposit(alice, DEFAULT_AMOUNT)
        allocate
        setARMBuffer(0.5 ether)
    {
        uint256 marketBalanceBefore = market.balanceOf(address(siloMarket));
        uint256 sharesBefore = market.convertToShares(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY);
        // Assertions before allocation
        assertApproxEqAbs(marketBalanceBefore, sharesBefore, 1, "shares before");
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets before");

        int256 expectedLiquidityDelta = getLiquidityDelta();
        uint256 expectedShares = market.previewWithdraw(abs(expectedLiquidityDelta));

        // Expected event
        vm.expectEmit(address(market));
        emit IERC4626.Withdraw(
            address(siloMarket), address(originARM), address(siloMarket), abs(expectedLiquidityDelta), expectedShares
        );
        vm.expectEmit(address(originARM));
        emit AbstractARM.Allocated(address(siloMarket), expectedLiquidityDelta, expectedLiquidityDelta);

        // Main call
        originARM.allocate();

        // Assertions after allocation
        assertEq(market.balanceOf(address(siloMarket)), marketBalanceBefore - expectedShares, "shares after");
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets after");
    }

    function test_Fork_Allocate_When_LiquidityDelta_IsNegative_FullWithdraw()
        public
        setARMBuffer(0)
        addMarket(address(siloMarket))
        setActiveMarket(address(siloMarket))
        deposit(alice, DEFAULT_AMOUNT)
        allocate
        setARMBuffer(1 ether)
    {
        uint256 marketBalanceBefore = market.balanceOf(address(siloMarket));
        uint256 sharesBefore = market.convertToShares(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY);
        // Assertions before allocation
        assertApproxEqAbs(marketBalanceBefore, sharesBefore, 1, "shares before");
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets before");

        int256 expectedLiquidityDelta = getLiquidityDelta();
        uint256 expectedShares = market.previewWithdraw(abs(expectedLiquidityDelta));
        assertApproxEqAbs(abs(expectedLiquidityDelta), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "expectedLiquidityDelta");

        // Expected event
        vm.expectEmit(address(market));
        emit IERC4626.Withdraw(
            address(siloMarket), address(originARM), address(siloMarket), abs(expectedLiquidityDelta), expectedShares
        );
        vm.expectEmit(address(originARM));
        emit AbstractARM.Allocated(address(siloMarket), expectedLiquidityDelta, expectedLiquidityDelta);

        // Main call
        originARM.allocate();

        // Assertions after allocation
        assertLe(market.balanceOf(address(siloMarket)), MIN_BALANCE, "shares after");
        assertApproxEqAbs(originARM.totalAssets(), DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets after");
    }

    function test_Fork_Allocate_When_LiquidityDelta_IsNegative_DesiredIsLessThanAvailable()
        public
        setFee(0)
        setARMBuffer(0)
        addMarket(address(siloMarket))
        setActiveMarket(address(siloMarket))
        deposit(alice, DEFAULT_AMOUNT)
        allocate
        setARMBuffer(1 ether)
        donate(os, address(originARM), 1 ether)
    {
        uint256 marketBalanceBefore = market.balanceOf(address(siloMarket));
        uint256 sharesBefore = market.convertToShares(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY);
        // Assertions before allocation
        assertApproxEqAbs(marketBalanceBefore, sharesBefore, 1, "shares before");
        assertApproxEqAbs(originARM.totalAssets(), 2 * DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 3, "totalAssets before");

        uint256 expectedShares = siloMarket.maxRedeem(address(originARM));
        uint256 expectedAmount = market.convertToAssets(expectedShares);
        int256 expectedLiquidityDelta = getLiquidityDelta();

        // Expected event
        vm.expectEmit(address(market));
        emit IERC4626.Withdraw(
            address(siloMarket), address(originARM), address(siloMarket), expectedAmount, expectedShares
        );
        vm.expectEmit(address(originARM));
        emit AbstractARM.Allocated(address(siloMarket), expectedLiquidityDelta, expectedLiquidityDelta);
        // Main call
        originARM.allocate();

        // Assertions after allocation
        assertEq(market.balanceOf(address(siloMarket)), marketBalanceBefore - expectedShares, "shares after");
        assertApproxEqAbs(originARM.totalAssets(), 2 * DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 3, "totalAssets after");
    }

    function test_Fork_Allocate_When_LiquidityDelta_IsNegative_NoShares()
        public
        setFee(0)
        setARMBuffer(0)
        addMarket(address(siloMarket))
        setActiveMarket(address(siloMarket))
        deposit(alice, DEFAULT_AMOUNT)
        allocate
        setARMBuffer(1 ether)
        allocate
        donate(os, address(originARM), DEFAULT_AMOUNT)
    {
        uint256 marketBalanceBefore = market.balanceOf(address(siloMarket));
        // Assertions before allocation
        assertLe(marketBalanceBefore, MIN_BALANCE, "shares before");
        // We ensure we are in the edge case where Silo has rounded issues.
        assertNotEq(marketBalanceBefore, 0, "shares before");
        assertApproxEqAbs(originARM.totalAssets(), 2 * DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets before");

        // Main call
        originARM.allocate();

        // Assertions after allocation
        assertEq(market.balanceOf(address(siloMarket)), marketBalanceBefore, "shares after");
        assertApproxEqAbs(originARM.totalAssets(), 2 * DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY, 1, "totalAssets after");
    }

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
