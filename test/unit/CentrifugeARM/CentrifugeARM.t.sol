// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {Proxy} from "contracts/Proxy.sol";
import {CentrifugeARM} from "contracts/CentrifugeARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {SiloMarket} from "contracts/markets/SiloMarket.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";
import {AbstractMultiAssetARM} from "contracts/AbstractMultiAssetARM.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MockERC20} from "dependencies/solmate-6.7.0/src/test/utils/mocks/MockERC20.sol";
import {MockERC4626Market} from "test/unit/mocks/MockERC4626Market.sol";
import {MockAsyncRedeemVault} from "test/unit/mocks/MockAsyncRedeemVault.sol";

contract CentrifugeARMTest is Test {
    uint256 internal constant CLAIM_DELAY = 1 days;
    uint256 internal constant DEFAULT_FEE = 1000;
    uint256 internal constant RAW_UNIT = 1e6;
    uint256 internal constant MIN_TOTAL_SUPPLY = 1e12;

    Proxy internal armProxy;
    Proxy internal capManagerProxy;
    Proxy internal marketProxy;

    CentrifugeARM internal rwaARM;
    CapManager internal capManager;
    SiloMarket internal siloMarket;
    IERC4626 internal market;

    MockERC20 internal usdc;
    MockAsyncRedeemVault internal rwa1;
    MockAsyncRedeemVault internal rwa2;
    MockAsyncRedeemVault internal badDecimalsVault;

    address internal deployer;
    address internal governor;
    address internal operator;
    address internal feeCollector;
    address internal alice;
    address internal bob;

    function setUp() public {
        deployer = makeAddr("deployer");
        governor = makeAddr("governor");
        operator = makeAddr("operator");
        feeCollector = makeAddr("feeCollector");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        usdc = new MockERC20("USD Coin", "USDC", 6);
        rwa1 = new MockAsyncRedeemVault(IERC20(address(usdc)), "RWA One", "RWA1", 6);
        rwa2 = new MockAsyncRedeemVault(IERC20(address(usdc)), "RWA Two", "RWA2", 6);
        badDecimalsVault = new MockAsyncRedeemVault(IERC20(address(usdc)), "Bad Decimals", "BAD", 18);
        market = IERC4626(address(new MockERC4626Market(IERC20(address(usdc)))));

        vm.startPrank(deployer);

        armProxy = new Proxy();
        capManagerProxy = new Proxy();
        marketProxy = new Proxy();

        rwaARM = new CentrifugeARM(address(usdc), CLAIM_DELAY, 1e7, 1e6);
        capManager = new CapManager(address(armProxy));
        siloMarket = new SiloMarket(address(armProxy), address(market), makeAddr("fake gauge"));

        usdc.mint(deployer, MIN_TOTAL_SUPPLY);
        usdc.approve(address(armProxy), MIN_TOTAL_SUPPLY);

        armProxy.initialize(
            address(rwaARM),
            governor,
            abi.encodeWithSelector(
                CentrifugeARM.initialize.selector,
                "Centrifuge ARM",
                "CARM",
                operator,
                DEFAULT_FEE,
                feeCollector,
                address(0)
            )
        );

        capManagerProxy.initialize(
            address(capManager), governor, abi.encodeWithSelector(CapManager.initialize.selector, operator)
        );

        marketProxy.initialize(
            address(siloMarket),
            governor,
            abi.encodeWithSelector(Abstract4626MarketWrapper.initialize.selector, operator, address(0x1))
        );

        vm.stopPrank();

        rwaARM = CentrifugeARM(address(armProxy));
        capManager = CapManager(address(capManagerProxy));
        siloMarket = SiloMarket(address(marketProxy));

        vm.startPrank(governor);
        rwaARM.addBaseAsset(address(rwa1), address(rwa1), 0.995e36, 1e36, 0.998e36);
        rwaARM.addBaseAsset(address(rwa2), address(rwa2), 0.994e36, 1.001e36, 0.999e36);
        vm.stopPrank();
    }

    function test_InitializeAndListSupportedAssets() public view {
        address[] memory assets = rwaARM.getSupportedBaseAssets();
        assertEq(assets.length, 2, "wrong supported asset count");
        assertEq(assets[0], address(rwa1), "wrong first asset");
        assertEq(assets[1], address(rwa2), "wrong second asset");
        assertEq(rwaARM.asset(), address(usdc), "wrong liquidity asset");
        assertTrue(rwaARM.isSupportedBaseAsset(address(rwa1)), "asset not supported");
    }

    function test_RevertWhen_AddBaseAsset_WithMismatchedDecimals() public {
        vm.prank(governor);
        vm.expectRevert("ARM: invalid asset decimals");
        rwaARM.addBaseAsset(address(badDecimalsVault), address(badDecimalsVault), 0.995e36, 1e36, 0.998e36);
    }

    function test_SetPricesAndCrossPrice_PerAsset() public {
        vm.prank(operator);
        rwaARM.setPrices(address(rwa1), 0.996e36, 1.0005e36);

        (uint256 buyPrice, uint256 sellPrice) = rwaARM.getPrices(address(rwa1));
        assertEq(buyPrice, 0.996e36, "wrong buy price");
        assertEq(sellPrice, 1.0005e36, "wrong sell price");

        vm.prank(governor);
        rwaARM.setCrossPrice(address(rwa1), 0.999e36);

        AbstractMultiAssetARM.BaseAssetConfig memory config = rwaARM.getBaseAssetConfig(address(rwa1));
        assertEq(config.crossPrice, 0.999e36, "wrong cross price");
    }

    function test_RevertWhen_BaseToBaseSwap() public {
        rwa1.mint(alice, 100 * RAW_UNIT);
        vm.startPrank(alice);
        rwa1.approve(address(rwaARM), type(uint256).max);
        vm.expectRevert("ARM: Invalid swap assets");
        rwaARM.swapExactTokensForTokens(IERC20(address(rwa1)), IERC20(address(rwa2)), 10 * RAW_UNIT, 0, alice);
        vm.stopPrank();
    }

    function test_SwapLiquidityForDifferentBaseAssets() public {
        usdc.mint(alice, 500 * RAW_UNIT);
        rwa1.mint(address(rwaARM), 500 * RAW_UNIT);
        rwa2.mint(address(rwaARM), 500 * RAW_UNIT);

        vm.startPrank(alice);
        usdc.approve(address(rwaARM), type(uint256).max);

        uint256[] memory firstSwap =
            rwaARM.swapExactTokensForTokens(IERC20(address(usdc)), IERC20(address(rwa1)), 100 * RAW_UNIT, 0, alice);
        uint256[] memory secondSwap =
            rwaARM.swapExactTokensForTokens(IERC20(address(usdc)), IERC20(address(rwa2)), 100 * RAW_UNIT, 0, alice);
        vm.stopPrank();

        assertEq(firstSwap[1], 100 * RAW_UNIT, "wrong rwa1 output");
        assertApproxEqAbs(secondSwap[1], 99_900_099, 1, "wrong rwa2 output");
    }

    function test_TotalAssets_IncludesBaseBalancesAndRequestedVaultRedeems() public {
        rwa1.mint(address(rwaARM), 100 * RAW_UNIT);
        rwa2.mint(address(rwaARM), 50 * RAW_UNIT);

        vm.prank(operator);
        rwaARM.requestVaultRedeem(address(rwa2), 20 * RAW_UNIT);

        uint256 expected = MIN_TOTAL_SUPPLY;
        expected += (100 * RAW_UNIT * 0.998e36) / 1e36;
        expected += (30 * RAW_UNIT * 0.999e36) / 1e36;
        expected += 20 * RAW_UNIT;
        expected -= 14_977_000;

        assertEq(rwaARM.totalAssets(), expected, "wrong total assets");
    }

    function test_DepositRedeemAndClaim_WithMultipleBaseAssetsPresent() public {
        rwa1.mint(address(rwaARM), 25 * RAW_UNIT);

        usdc.mint(alice, 500 * RAW_UNIT);
        vm.startPrank(alice);
        usdc.approve(address(rwaARM), type(uint256).max);
        uint256 mintedShares = rwaARM.deposit(100 * RAW_UNIT);
        (uint256 requestId, uint256 requestedAssets) = rwaARM.requestRedeem(mintedShares);
        vm.warp(block.timestamp + CLAIM_DELAY);
        uint256 claimed = rwaARM.claimRedeem(requestId);
        vm.stopPrank();

        assertEq(claimed, requestedAssets, "wrong claimed amount");
        assertEq(usdc.balanceOf(alice), 500 * RAW_UNIT - 100 * RAW_UNIT + requestedAssets, "wrong final balance");
    }

    function test_PerformanceFeeUsesAggregatePortfolioIncrease() public {
        usdc.mint(alice, 200 * RAW_UNIT);
        vm.startPrank(alice);
        usdc.approve(address(rwaARM), type(uint256).max);
        rwaARM.deposit(100 * RAW_UNIT);
        vm.stopPrank();

        rwa1.mint(address(rwaARM), 100 * RAW_UNIT);
        rwa1.setPricePerShare(1.1e6);

        uint256 fees = rwaARM.feesAccrued();
        assertEq(fees, 10_978_000, "wrong accrued fees");
    }

    function test_RequestAndClaimVaultRedeem_PerAsset() public {
        rwa1.mint(address(rwaARM), 100 * RAW_UNIT);
        usdc.mint(address(rwa1), 100 * RAW_UNIT);

        vm.prank(operator);
        rwaARM.requestVaultRedeem(address(rwa1), 40 * RAW_UNIT);

        AbstractMultiAssetARM.BaseAssetConfig memory config = rwaARM.getBaseAssetConfig(address(rwa1));
        assertEq(config.requestedVaultShares, 40 * RAW_UNIT, "wrong requested shares");
        assertEq(rwa1.balanceOf(address(rwaARM)), 60 * RAW_UNIT, "wrong on hand shares");

        rwa1.setClaimableRedeemShares(address(rwaARM), 25 * RAW_UNIT);

        vm.prank(operator);
        uint256 assetsOut = rwaARM.claimVaultRedeem(address(rwa1), 25 * RAW_UNIT);

        config = rwaARM.getBaseAssetConfig(address(rwa1));
        assertEq(assetsOut, 25 * RAW_UNIT, "wrong assets out");
        assertEq(config.requestedVaultShares, 15 * RAW_UNIT, "wrong remaining requested shares");
        assertEq(usdc.balanceOf(address(rwaARM)), MIN_TOTAL_SUPPLY + 25 * RAW_UNIT, "wrong liquidity balance");
    }

    function test_RemoveBaseAsset_BlockedUntilBalancesAndRequestsClear() public {
        rwa1.mint(address(rwaARM), MIN_TOTAL_SUPPLY);

        vm.prank(governor);
        vm.expectRevert("ARM: too many base assets");
        rwaARM.removeBaseAsset(address(rwa1));

        rwa1.burn(address(rwaARM), MIN_TOTAL_SUPPLY);
        rwa1.mint(address(rwaARM), 10 * RAW_UNIT);
        usdc.mint(address(rwa1), 10 * RAW_UNIT);

        vm.prank(operator);
        rwaARM.requestVaultRedeem(address(rwa1), 10 * RAW_UNIT);

        vm.prank(governor);
        vm.expectRevert("ARM: pending vault redeems");
        rwaARM.removeBaseAsset(address(rwa1));

        rwa1.setClaimableRedeemShares(address(rwaARM), 10 * RAW_UNIT);
        vm.prank(operator);
        rwaARM.claimVaultRedeem(address(rwa1), 10 * RAW_UNIT);

        vm.prank(governor);
        rwaARM.removeBaseAsset(address(rwa1));

        assertFalse(rwaARM.isSupportedBaseAsset(address(rwa1)), "asset still supported");
    }

    function test_Allocate_OnlyTouchesLiquidityMarket() public {
        usdc.mint(alice, 500 * RAW_UNIT);
        vm.startPrank(alice);
        usdc.approve(address(rwaARM), type(uint256).max);
        rwaARM.deposit(200 * RAW_UNIT);
        vm.stopPrank();

        rwa1.mint(address(rwaARM), 100 * RAW_UNIT);

        address[] memory markets = new address[](1);
        markets[0] = address(siloMarket);

        vm.startPrank(governor);
        rwaARM.addMarkets(markets);
        vm.stopPrank();

        vm.startPrank(operator);
        rwaARM.setARMBuffer(0);
        rwaARM.setActiveMarket(address(siloMarket));
        vm.stopPrank();

        assertGt(IERC4626(address(siloMarket)).balanceOf(address(rwaARM)), 0, "market not funded");
        assertEq(rwa1.balanceOf(address(rwaARM)), 100 * RAW_UNIT, "base asset touched by allocation");
    }
}
