// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract Unit_Concrete_OriginARM_TotalAssets_Test_ is Unit_Shared_Test {
    function test_TotalAssets_RightAfterDeployment() public view {
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "Wrong total assets");
    }

    /// requestingOriginWithdrawal should have no impact on total assets
    function test_TotalAssets_When_ExternalWithdrawQueue_IsNotZero() public swapAllWETHForOETH {
        // Check the total assets before
        uint256 totalAssetsBefore = originARM.totalAssets();

        vm.prank(governor);
        originARM.requestOriginWithdrawal(MIN_TOTAL_SUPPLY / 2);

        // Ensure the total assets is equal to the external withdraw queue
        assertEq(originARM.totalAssets(), totalAssetsBefore, "Wrong total assets");
    }

    /// allocating to a market should have no impact on total assets
    function test_TotalAssets_When_ActiveMarket() public addMarket(address(market)) setActiveMarket(address(market)) {
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "Wrong total assets");
    }

    /// deposit then redeem should have no impact on total assets
    function test_TotalAssets_When_WithdrawQueue_IsNotZero() public deposit(alice, 1 ether) requestRedeemAll(alice) {
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "Wrong total assets");
    }

    /// market take a 100% loss, totalAssets should be MIN_TOTAL_SUPPLY
    function test_TotalAssets_When_MarketLoseAll()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        deposit(alice, 1 ether)
        setARMBuffer(0)
        allocate
        simulateMarketLoss(address(market), 1 ether)
        requestRedeem(alice, 1 ether)
    {
        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "Wrong total assets");
    }

    function test_TotalAssets_When_AssetIsLessThanOutstandingWithdrawals()
        public
        deposit(alice, DEFAULT_AMOUNT)
        requestRedeemAll(alice)
    {
        // Simulate a loss on the ARM
        deal(address(weth), address(originARM), 0);

        assertEq(originARM.totalAssets(), MIN_TOTAL_SUPPLY, "Wrong total assets");
    }

    function test_TotalAssets_UsesConvertToAssets_When_PreviewRedeem_IsLiquidityConstrained()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        deposit(alice, DEFAULT_AMOUNT)
        setARMBuffer(0)
        allocate
    {
        uint256 marketShares = market.balanceOf(address(originARM));
        uint256 marketValue = market.convertToAssets(marketShares);
        uint256 totalAssetsBefore = originARM.totalAssets();
        uint256 assetsPerShareBefore = originARM.convertToAssets(1 ether);

        assertGt(marketValue, 0, "market should have value after allocation");

        vm.mockCall(address(market), abi.encodeWithSelector(IERC4626.previewRedeem.selector), abi.encode(0));
        vm.mockCall(address(market), abi.encodeWithSelector(IERC4626.maxWithdraw.selector), abi.encode(0));
        vm.mockCall(address(market), abi.encodeWithSelector(IERC4626.maxRedeem.selector), abi.encode(0));

        assertEq(originARM.totalAssets(), totalAssetsBefore, "total assets should use convertToAssets");
        assertEq(originARM.convertToAssets(1 ether), assetsPerShareBefore, "asset per share should be unchanged");
        assertEq(originARM.claimable(), 0, "claimable should still reflect liquidity constraints");
        assertEq(market.previewRedeem(marketShares), 0, "previewRedeem should be constrained");
        assertEq(market.convertToAssets(marketShares), marketValue, "convertToAssets should still show economic value");
    }
}
