// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_MultiAssetARM_Test} from "./Base.t.sol";

// Contracts
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {Proxy} from "contracts/Proxy.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Mocks
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockAssetAdapter} from "./mocks/MockAssetAdapter.sol";
import {MockERC4626Market} from "./mocks/MockERC4626Market.sol";

abstract contract Unit_MultiAssetARM_Shared_Test is Base_MultiAssetARM_Test {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual {
        deployMockContracts();
        deployContracts();
        labelAll();
        approveSpending();
    }

    function deployMockContracts() internal virtual {
        liquidity = IERC20(address(new MockERC20("Liquidity Asset", "LIQ", liquidityDecimals())));
        peg6 = IERC20(address(new MockERC20("Pegged 6", "PEG6", 6)));
        peg18 = IERC20(address(new MockERC20("Pegged 18", "PEG18", 18)));
        adp6 = IERC20(address(new MockERC20("Adapter 6", "ADP6", 6)));
        adp18 = IERC20(address(new MockERC20("Adapter 18", "ADP18", 18)));
        market = new MockERC4626Market(liquidity);
        market2 = new MockERC4626Market(liquidity);
    }

    function deployContracts() internal virtual {
        vm.startPrank(deployer);

        Proxy armProxy = new Proxy();
        Proxy capManagerProxy = new Proxy();

        MultiAssetARM armLogic = new MultiAssetARM({
            _liquidityAsset: address(liquidity),
            _claimDelay: CLAIM_DELAY,
            _minSharesToRedeem: MIN_SHARES_TO_REDEEM,
            _allocateThreshold: int256(LIQUIDITY_UNIT()) // 1 liquidity token
        });
        CapManager capManagerLogic = new CapManager({_arm: address(armProxy)});

        // Initialization pulls MIN_LIQUIDITY of the liquidity asset from the deployer.
        _mint(liquidity, deployer, MIN_LIQUIDITY());
        liquidity.approve(address(armProxy), MIN_LIQUIDITY());

        armProxy.initialize(
            address(armLogic),
            governor,
            abi.encodeWithSelector(
                MultiAssetARM.initialize.selector,
                "Multi-Asset ARM",
                "MA-ARM",
                operator,
                DEFAULT_FEE,
                feeCollector,
                address(capManagerProxy)
            )
        );

        capManagerProxy.initialize(
            address(capManagerLogic), governor, abi.encodeWithSelector(CapManager.initialize.selector, operator)
        );
        vm.stopPrank();

        arm = MultiAssetARM(payable(address(armProxy)));
        capManager = CapManager(address(capManagerProxy));

        // One adapter per base asset (asset() == liquidity).
        adapterPeg6 = new MockAssetAdapter(address(arm), address(peg6), address(liquidity));
        adapterPeg18 = new MockAssetAdapter(address(arm), address(peg18), address(liquidity));
        adapterAdp6 = new MockAssetAdapter(address(arm), address(adp6), address(liquidity));
        adapterAdp18 = new MockAssetAdapter(address(arm), address(adp18), address(liquidity));

        // Register the base-asset matrix. Overridable so admin/management tests can start from a
        // clean slate and register on demand.
        _registerInitialBaseAssets();

        // Pre-fund the adapter-backed adapters with liquidity so claims can pay out.
        _mint(liquidity, address(adapterAdp6), 1_000_000 * LIQUIDITY_UNIT());
        _mint(liquidity, address(adapterAdp18), 1_000_000 * LIQUIDITY_UNIT());
    }

    /// @dev Registers the 6/18 x pegged/adapter base-asset matrix. Override to a no-op to start clean.
    function _registerInitialBaseAssets() internal virtual {
        _registerBaseAsset(peg6, address(adapterPeg6), true);
        _registerBaseAsset(peg18, address(adapterPeg18), true);
        _registerBaseAsset(adp6, address(adapterAdp6), false);
        _registerBaseAsset(adp18, address(adapterAdp18), false);
    }

    function _registerBaseAsset(IERC20 token, address adapter, bool _pegged) internal {
        vm.prank(governor);
        arm.addBaseAsset(
            address(token), adapter, BUY_PRICE, SELL_PRICE, type(uint128).max, type(uint128).max, CROSS_PRICE, _pegged
        );
    }

    function labelAll() internal virtual {
        vm.label(address(arm), "MULTI-ASSET ARM PROXY");
        vm.label(address(capManager), "CAP MANAGER PROXY");
        vm.label(address(liquidity), "LIQUIDITY");
        vm.label(address(peg6), "PEG6");
        vm.label(address(peg18), "PEG18");
        vm.label(address(adp6), "ADP6");
        vm.label(address(adp18), "ADP18");
        vm.label(address(market), "ERC4626 MARKET (MOCK)");
        vm.label(address(market2), "ERC4626 MARKET 2 (MOCK)");
    }

    function approveSpending() internal virtual {
        address[2] memory users = [alice, bobby];
        for (uint256 i; i < users.length; ++i) {
            vm.startPrank(users[i]);
            liquidity.approve(address(arm), type(uint256).max);
            peg6.approve(address(arm), type(uint256).max);
            peg18.approve(address(arm), type(uint256).max);
            adp6.approve(address(arm), type(uint256).max);
            adp18.approve(address(arm), type(uint256).max);
            vm.stopPrank();
        }
    }

    //////////////////////////////////////////////////////
    /// --- TOKEN HELPERS
    //////////////////////////////////////////////////////
    function _mint(IERC20 token, address to, uint256 amount) internal {
        MockERC20(address(token)).mint(to, amount);
    }

    function dealLiquidityToARM(uint256 amount) internal {
        _mint(liquidity, address(arm), amount);
    }

    function dealBaseToARM(IERC20 token, uint256 amount) internal {
        _mint(token, address(arm), amount);
    }

    function dealBaseToUser(IERC20 token, address user, uint256 amount) internal {
        _mint(token, user, amount);
        vm.prank(user);
        token.approve(address(arm), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- LP HELPERS
    //////////////////////////////////////////////////////
    function firstDeposit(address user, uint256 amount) internal returns (uint256 shares) {
        _mint(liquidity, user, amount);
        vm.startPrank(user);
        liquidity.approve(address(arm), type(uint256).max);
        shares = arm.deposit(amount);
        vm.stopPrank();
    }

    function aliceFirstDeposit() internal returns (uint256) {
        return firstDeposit(alice, DEFAULT_AMOUNT());
    }

    function bobbyFirstDeposit() internal returns (uint256) {
        return firstDeposit(bobby, DEFAULT_AMOUNT());
    }

    function aliceFirstDeposit(uint256 amount) internal returns (uint256) {
        return firstDeposit(alice, amount);
    }

    function bobbyFirstDeposit(uint256 amount) internal returns (uint256) {
        return firstDeposit(bobby, amount);
    }

    function requestRedeem(address user, uint256 shares) internal returns (uint256 requestId, uint256 assets) {
        if (shares == 0) shares = arm.balanceOf(user);
        vm.prank(user);
        (requestId, assets) = arm.requestRedeem(shares);
    }

    function aliceRequest(uint256 shares) internal returns (uint256 requestId, uint256 assets) {
        return requestRedeem(alice, shares);
    }

    function bobbyRequest(uint256 shares) internal returns (uint256 requestId, uint256 assets) {
        return requestRedeem(bobby, shares);
    }

    function _assertStoredRequest(
        uint256 requestId,
        address expectedWithdrawer,
        uint256 expectedClaimTimestamp,
        uint256 expectedAssets,
        uint256 expectedQueued,
        uint256 expectedShares
    ) internal view {
        (address withdrawer, bool claimed, uint40 claimTimestamp, uint128 storedAssets, uint128 storedQueued) =
            arm.withdrawalRequests(requestId);
        uint256 storedShares = arm.withdrawalRequestShares(requestId);
        assertEq(withdrawer, expectedWithdrawer, "req.withdrawer");
        assertEq(claimed, false, "req.claimed");
        assertEq(claimTimestamp, expectedClaimTimestamp, "req.claimTimestamp");
        assertEq(storedAssets, expectedAssets, "req.assets");
        assertEq(storedQueued, expectedQueued, "req.queued");
        assertEq(storedShares, expectedShares, "req.shares");
    }

    //////////////////////////////////////////////////////
    /// --- MARKET / CAP HELPERS
    //////////////////////////////////////////////////////
    function desactiveCapManager() internal {
        vm.prank(governor);
        arm.setCapManager(address(0));
    }

    function addMarket(address _market) internal {
        address[] memory markets = new address[](1);
        markets[0] = _market;
        vm.prank(governor);
        arm.addMarkets(markets);
    }

    function setActiveMarket(address _market) internal {
        vm.prank(governor);
        arm.setActiveMarket(_market);
    }

    function setARMBuffer(uint256 buffer) internal {
        vm.prank(governor);
        arm.setARMBuffer(buffer);
    }

    //////////////////////////////////////////////////////
    /// --- baseAssetConfigs GETTERS (9-field tuple)
    //////////////////////////////////////////////////////
    function buyPrice(IERC20 token) internal view returns (uint256 v) {
        (v,,,,,,,,) = arm.baseAssetConfigs(address(token));
    }

    function sellPrice(IERC20 token) internal view returns (uint256 v) {
        (, v,,,,,,,) = arm.baseAssetConfigs(address(token));
    }

    function buyLiquidityRemaining(IERC20 token) internal view returns (uint256 v) {
        (,, v,,,,,,) = arm.baseAssetConfigs(address(token));
    }

    function sellLiquidityRemaining(IERC20 token) internal view returns (uint256 v) {
        (,,, v,,,,,) = arm.baseAssetConfigs(address(token));
    }

    function crossPrice(IERC20 token) internal view returns (uint256 v) {
        (,,,, v,,,,) = arm.baseAssetConfigs(address(token));
    }

    function pendingRedeemAssets(IERC20 token) internal view returns (uint256 v) {
        (,,,,, v,,,) = arm.baseAssetConfigs(address(token));
    }

    function pegged(IERC20 token) internal view returns (bool v) {
        (,,,,,, v,,) = arm.baseAssetConfigs(address(token));
    }

    function baseDecimals(IERC20 token) internal view returns (uint8 v) {
        (,,,,,,, v,) = arm.baseAssetConfigs(address(token));
    }

    function adapterOf(IERC20 token) internal view returns (address v) {
        (,,,,,,,, v) = arm.baseAssetConfigs(address(token));
    }

    //////////////////////////////////////////////////////
    /// --- FEE HELPER
    //////////////////////////////////////////////////////
    function expectedBuySideFee(IERC20 token, uint256 amountOut) internal view returns (uint256) {
        uint256 assetBuyPrice = buyPrice(token);
        uint256 assetCrossPrice = crossPrice(token);
        uint256 feeMultiplier = assetBuyPrice == 0
            ? 0
            : (assetCrossPrice - assetBuyPrice) * uint256(arm.fee()) * PRICE_SCALE / (assetBuyPrice * FEE_SCALE);
        return amountOut * feeMultiplier / PRICE_SCALE;
    }
}
