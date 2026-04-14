// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MorphoBlueSupplyVault} from "contracts/markets/MorphoBlueSupplyVault.sol";
import {Id, MarketParams} from "contracts/morpho/IMorpho.sol";
import {MarketParamsLib} from "contracts/morpho/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "contracts/morpho/libraries/MorphoBalancesLib.sol";
import {MockMorphoBlue} from "test/unit/mocks/MockMorphoBlue.sol";
import {MockMorphoIrm} from "test/unit/mocks/MockMorphoIrm.sol";

contract MorphoBlueSupplyVaultTest is Test {
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for MockMorphoBlue;

    MockERC20 internal asset;
    MockMorphoBlue internal morpho;
    MockMorphoIrm internal irm;
    MorphoBlueSupplyVault internal vault;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    MarketParams internal marketParams;
    Id internal marketId;

    function setUp() public {
        asset = new MockERC20("Wrapped ETH", "WETH", 18);
        morpho = new MockMorphoBlue();
        irm = new MockMorphoIrm();

        marketParams = MarketParams({
            loanToken: address(asset),
            collateralToken: makeAddr("collateral"),
            oracle: makeAddr("oracle"),
            irm: address(irm),
            lltv: 0.86e18
        });
        marketId = marketParams.id();

        morpho.createMarket(marketParams);
        vault = new MorphoBlueSupplyVault(address(morpho), marketParams);

        asset.mint(alice, 1_000 ether);
        asset.mint(bob, 1_000 ether);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
    }

    function test_Deposit_MintsWrapperSharesMatchingMorphoSupplyShares() public {
        uint256 shares = _deposit(alice, 100 ether);

        assertEq(vault.balanceOf(alice), shares, "alice wrapper shares");
        assertEq(morpho.position(marketId, address(vault)).supplyShares, shares, "vault morpho shares");
        assertEq(vault.totalSupply(), shares, "wrapper total supply");
        assertEq(vault.previewRedeem(shares), 100 ether, "redeem preview");
    }

    function test_DerivesNameAndSymbolFromLoanToken() public view {
        assertEq(vault.name(), "Morpho Blue WETH Supply", "name");
        assertEq(vault.symbol(), "mbWETH", "symbol");
    }

    function test_TotalAssets_IncludesNotYetAccruedInterest() public {
        _deposit(alice, 100 ether);

        vm.warp(2 days);
        morpho.setTotalBorrowAssets(marketParams, 60 ether);
        morpho.setLastUpdate(marketParams, uint128(block.timestamp - 1 days));
        irm.setBorrowRatePerSecond(1e10);

        uint256 rawAssets = morpho.market(marketId).totalSupplyAssets;
        uint256 expectedAssets = morpho.expectedSupplyAssets(marketParams, address(vault));

        assertGt(expectedAssets, rawAssets, "expected assets should include accrued interest");
        assertEq(vault.convertToAssets(vault.totalSupply()), expectedAssets, "assets per share");
    }

    function test_MaxWithdraw_IsCappedByMorphoLiquidity() public {
        _deposit(alice, 100 ether);

        morpho.setTotalBorrowAssets(marketParams, 90 ether);

        assertEq(vault.maxWithdraw(alice), 10 ether, "max withdraw");

        uint256 redeemableShares = vault.maxRedeem(alice);
        assertEq(vault.previewRedeem(redeemableShares), 10 ether, "max redeem in assets");
    }

    function test_Withdraw_BurnsExactSharesReturnedByMorpho() public {
        uint256 sharesBefore = _deposit(alice, 100 ether);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(40 ether, alice, alice);

        assertLt(sharesBurned, sharesBefore, "shares burned");
        assertEq(vault.balanceOf(alice), sharesBefore - sharesBurned, "alice shares after");
        assertEq(asset.balanceOf(alice), 940 ether, "alice assets after");
        assertEq(morpho.position(marketId, address(vault)).supplyShares, vault.totalSupply(), "wrapped shares stay synced");
    }

    function test_Redeem_WithAllowance() public {
        uint256 shares = _deposit(alice, 100 ether);

        vm.prank(alice);
        vault.approve(bob, shares / 2);

        vm.prank(bob);
        uint256 assets = vault.redeem(shares / 2, bob, alice);

        assertEq(assets, vault.previewRedeem(shares / 2), "redeemed assets");
        assertEq(asset.balanceOf(bob), 1_000 ether + assets, "bob received assets");
        assertEq(vault.balanceOf(alice), shares / 2, "alice remaining shares");
    }

    function _deposit(address user, uint256 assets) internal returns (uint256 shares) {
        vm.prank(user);
        shares = vault.deposit(assets, user);
    }
}
