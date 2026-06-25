// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "./Base.t.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {StETHAssetAdapter} from "contracts/adapters/StETHAssetAdapter.sol";
import {WstETHAssetAdapter} from "contracts/adapters/WstETHAssetAdapter.sol";
import {AbstractLidoAssetAdapter} from "contracts/adapters/AbstractLidoAssetAdapter.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Mocks
import {WETH} from "@solmate/tokens/WETH.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockWstETH} from "./mocks/MockWstETH.sol";
import {MockERC4626Market} from "./mocks/MockERC4626Market.sol";
import {MockLidoWithdraw} from "./mocks/MockLidoWithdraw.sol";

abstract contract Unit_LidoARM_Shared_Test is Base_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual {
        // Deploy Mock contracts
        deployMockContracts();

        // Deploy contracts
        deployContracts();

        // Label contracts
        labelAll();

        // Approve spending
        approveSpending();
    }

    function deployMockContracts() internal virtual {
        weth = IERC20(address(new WETH()));
        steth = IERC20(address(new MockERC20("Staked Ether", "stETH", 18)));
        mockERC4626Market = new MockERC4626Market(weth);
        mockERC4626Market2 = new MockERC4626Market(weth);
        mockWstETH = new MockWstETH(steth);
        wsteth = IERC20(address(mockWstETH));
        lidoWithdrawalQueue = new MockLidoWithdraw(address(steth));
    }

    function deployContracts() internal virtual {
        vm.startPrank(deployer);

        // --- Deploy Proxies
        Proxy lidoARMProxy = new Proxy();
        Proxy capManagerProxy = new Proxy();
        Proxy stETHAssetAdapterProxy = new Proxy();
        Proxy wstETHAssetAdapterProxy = new Proxy();

        // --- Deploy Logic contracts
        LidoARM lidoARMLogic = new LidoARM({
            _weth: address(weth),
            _claimDelay: CLAIM_DELAY,
            _minSharesToRedeem: MIN_SHARES_TO_REDEEM,
            _allocateThreshold: 1 ether
        });
        CapManager capManagerLogic = new CapManager({_arm: address(lidoARMProxy)});
        StETHAssetAdapter stETHAssetAdapterLogic = new StETHAssetAdapter({
            _arm: address(lidoARMProxy),
            _weth: address(weth),
            _steth: address(steth),
            _lidoWithdrawalQueue: address(lidoWithdrawalQueue)
        });
        WstETHAssetAdapter wstETHAssetAdapterLogic = new WstETHAssetAdapter({
            _arm: address(lidoARMProxy),
            _weth: address(weth),
            _steth: address(steth),
            _wsteth: address(wsteth),
            _lidoWithdrawalQueue: address(lidoWithdrawalQueue)
        });

        // Initialization requires 1e12 liquid assets to mint to dead address.
        // Mint 1e12 liquid assets to the deployer.
        deal(address(weth), deployer, 1e12);
        // Deployer approve the proxy to transfer 1e12 liquid assets.
        weth.approve(address(lidoARMProxy), 1e12);

        // --- Initialize Proxies
        // LidoARM Proxy
        lidoARMProxy.initialize(
            address(lidoARMLogic),
            governor,
            abi.encodeWithSelector(
                LidoARM.initialize.selector,
                "Lido ARM",
                "LIDO-ARM",
                operator,
                DEFAULT_FEE,
                feeCollector,
                address(capManagerProxy)
            )
        );

        // CapManager Proxy
        capManagerProxy.initialize(
            address(capManagerLogic),
            governor,
            abi.encodeWithSelector(CapManager.initialize.selector, address(lidoARMProxy))
        );

        // StETHAssetAdapter Proxy. Run `initialize()` through the proxy so the adapter
        // approves the lido withdrawal queue from the proxy's storage, not the impl's.
        stETHAssetAdapterProxy.initialize(
            address(stETHAssetAdapterLogic),
            governor,
            abi.encodeWithSelector(AbstractLidoAssetAdapter.initialize.selector)
        );

        // WstETHAssetAdapter Proxy. Same rationale as above.
        wstETHAssetAdapterProxy.initialize(
            address(wstETHAssetAdapterLogic),
            governor,
            abi.encodeWithSelector(AbstractLidoAssetAdapter.initialize.selector)
        );

        vm.stopPrank();

        // --- Set the proxy's implementation to the logic contract
        lidoARM = LidoARM(payable(address(lidoARMProxy)));
        capManager = CapManager(address(capManagerProxy));
        stETHAssetAdapter = StETHAssetAdapter(payable(address(stETHAssetAdapterProxy)));
        wstETHAssetAdapter = WstETHAssetAdapter(payable(address(wstETHAssetAdapterProxy)));
    }

    function labelAll() public virtual {
        vm.label(address(weth), "WETH");
        vm.label(address(steth), "STETH");
        vm.label(address(wsteth), "WSTETH");
        vm.label(address(mockWstETH), "WSTETH");
        vm.label(address(lidoARM), "LIDO ARM PROXY");
        vm.label(address(capManager), "CAP MANAGER PROXY");
        vm.label(address(stETHAssetAdapter), "STETH ASSET ADAPTER PROXY");
        vm.label(address(wstETHAssetAdapter), "WSTETH ASSET ADAPTER PROXY");
        vm.label(address(lidoWithdrawalQueue), "LIDO WITHDRAWAL QUEUE (MOCK)");
        vm.label(address(mockERC4626Market), "ERC4626 MARKET (MOCK)");
        vm.label(address(mockERC4626Market2), "ERC4626 MARKET 2 (MOCK)");
    }

    function approveSpending() internal {
        vm.startPrank(alice);
        weth.approve(address(lidoARM), type(uint256).max);
        steth.approve(address(lidoARM), type(uint256).max);
        wsteth.approve(address(lidoARM), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bobby);
        weth.approve(address(lidoARM), type(uint256).max);
        steth.approve(address(lidoARM), type(uint256).max);
        wsteth.approve(address(lidoARM), type(uint256).max);
        vm.stopPrank();
    }

    function desactiveCapManager() internal {
        vm.prank(governor);
        lidoARM.setCapManager(address(0));
    }

    function addMarket(address market) internal {
        address[] memory markets = new address[](1);
        markets[0] = market;
        vm.prank(governor);
        lidoARM.addMarkets(markets);
    }

    function setActiveMarket(address market) internal {
        vm.prank(governor);
        lidoARM.setActiveMarket(market);
    }

    function setARMBuffer(uint256 buffer) internal {
        vm.prank(governor);
        lidoARM.setARMBuffer(buffer);
    }

    function aliceFirstDeposit() internal {
        aliceFirstDeposit(100 ether);
    }

    function bobbyFirstDeposit() internal {
        bobbyFirstDeposit(100 ether);
    }

    function aliceFirstDeposit(uint256 amount) internal {
        firstDeposit(alice, amount);
    }

    function bobbyFirstDeposit(uint256 amount) internal {
        firstDeposit(bobby, amount);
    }

    function firstDeposit(address user, uint256 amount) internal {
        vm.startPrank(user);
        // Give the user some WETH
        deal(address(weth), user, amount);
        // The user approve LidoARM to spend his WETH
        weth.approve(address(lidoARM), type(uint256).max);
        // The user deposit the specified amount of WETH to LidoARM
        lidoARM.deposit(amount);
        vm.stopPrank();
    }

    function addBaseAsset(IERC20 token) internal {
        vm.prank(governor);
        if (token == steth) {
            lidoARM.addBaseAsset(
                address(steth),
                address(stETHAssetAdapter),
                992 * 1e33,
                1001 * 1e33,
                type(uint128).max,
                type(uint128).max,
                1e36,
                true
            );
        } else if (token == wsteth) {
            lidoARM.addBaseAsset(
                address(wsteth),
                address(wstETHAssetAdapter),
                992 * 1e33,
                1001 * 1e33,
                type(uint128).max,
                type(uint128).max,
                1e36,
                false
            );
        } else {
            revert("Unsupported token");
        }
    }

    function buyPrice(IERC20 token) internal view returns (uint256) {
        (uint128 _buyPrice,,,,,,,,) = lidoARM.baseAssetConfigs(address(token));
        return _buyPrice;
    }

    function sellPrice(IERC20 token) internal view returns (uint256) {
        (, uint128 _sellPrice,,,,,,,) = lidoARM.baseAssetConfigs(address(token));
        return _sellPrice;
    }

    function buyLiquidityRemaining(IERC20 token) internal view returns (uint256) {
        (,, uint128 _buyLiquidityRemaining,,,,,,) = lidoARM.baseAssetConfigs(address(token));
        return _buyLiquidityRemaining;
    }

    function sellLiquidityRemaining(IERC20 token) internal view returns (uint256) {
        (,,, uint128 _sellLiquidityRemaining,,,,,) = lidoARM.baseAssetConfigs(address(token));
        return _sellLiquidityRemaining;
    }

    function crossPrice(IERC20 token) internal view returns (uint256) {
        (,,,, uint128 _crossPrice,,,,) = lidoARM.baseAssetConfigs(address(token));
        return _crossPrice;
    }

    function pendingRedeemAssets(IERC20 token) internal view returns (uint256) {
        (,,,,, uint128 _pendingRedeemAssets,,,) = lidoARM.baseAssetConfigs(address(token));
        return _pendingRedeemAssets;
    }

    function expectedBuySideFee(IERC20 token, uint256 amountOut) internal view returns (uint256) {
        uint256 assetBuyPrice = buyPrice(token);
        uint256 assetCrossPrice = crossPrice(token);
        uint256 feeMultiplier = assetBuyPrice == 0
            ? 0
            : (assetCrossPrice - assetBuyPrice) * uint256(lidoARM.fee()) * PRICE_SCALE / (assetBuyPrice * FEE_SCALE);

        return amountOut * feeMultiplier / PRICE_SCALE;
    }

    function seedWstETHWithTargetExchangeRate() internal {
        uint256 initialStETH = 100 ether;
        uint256 accruedStETHRewards = 23.7 ether;
        address deadHolder = address(0xdead);

        // Seed the wrapper with a real wstETH supply. We start by wrapping 100 stETH, which mints 100 wstETH
        // shares because the ERC4626 exchange rate is still 1:1 when total supply is zero.
        deal(address(steth), deadHolder, initialStETH);

        vm.startPrank(deadHolder);
        // The mock wstETH uses ERC4626 deposit semantics under the hood, so the holder must approve stETH first.
        steth.approve(address(wsteth), initialStETH);
        // Mint wstETH shares to deadHolder and lock them there so tests start from a non-empty wrapper.
        mockWstETH.wrap(initialStETH);
        vm.stopPrank();

        // Donate stETH directly to the wrapper, like rebasing stETH rewards accruing behind existing wstETH shares.
        // After this, the vault has 123.7 stETH backing 100 wstETH.
        // That gives: 1 wstETH = 1.237 stETH = 1.237 WETH.
        MockERC20(address(steth)).mint(address(wsteth), accruedStETHRewards);

        assertEq(
            mockWstETH.getStETHByWstETH(1 ether),
            1.237 ether,
            "1 wstETH should be worth 1.237 stETH after seeding the exchange rate"
        );
    }

    function dealWsteth(address to, uint256 amount) internal {
        // Do not use Forge's deal(address(wsteth), to, amount) here. wstETH is an ERC4626-style vault token, so
        // directly editing the share balance would bypass the underlying stETH transfer and break vault accounting.
        //
        // Instead, calculate how much stETH is needed to mint the requested amount of wstETH shares, then go
        // through the normal ERC4626 mint path. This keeps totalSupply, the holder's wstETH shares, and the
        // wrapper's stETH assets consistent with each other.
        address from = address(0xfeed);
        require(wsteth.balanceOf(from) == 0, "from address should start with 0 wstETH");

        // amount is denominated in wstETH shares. If the wrapper has accrued rewards, 1 wstETH is worth more
        // than 1 stETH, so minting amount shares requires more than amount stETH.
        uint256 requiredStETH = mockWstETH.previewMint(amount);
        deal(address(steth), from, requiredStETH);

        vm.startPrank(from);
        // The mock wstETH pulls stETH during mint, so the temporary holder must approve the wrapper first.
        steth.approve(address(wsteth), requiredStETH);
        mockWstETH.mint(amount, from);
        wsteth.transfer(to, amount);
        vm.stopPrank();
    }

    function aliceRequest(uint256 sharesToRedeem) internal returns (uint256 requestId, uint256 assets) {
        return requestRedeem(alice, sharesToRedeem);
    }

    function bobbyRequest(uint256 sharesToRedeem) internal returns (uint256 requestId, uint256 assets) {
        return requestRedeem(bobby, sharesToRedeem);
    }

    function requestRedeem(address user, uint256 sharesToRedeem) internal returns (uint256 requestId, uint256 assets) {
        if (sharesToRedeem == 0) {
            sharesToRedeem = lidoARM.balanceOf(user);
        }
        vm.prank(user);
        (requestId, assets) = lidoARM.requestRedeem(sharesToRedeem);
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
            lidoARM.withdrawalRequests(requestId);
        uint256 storedShares = lidoARM.withdrawalRequestShares(requestId);
        assertEq(withdrawer, expectedWithdrawer, "req.withdrawer");
        assertEq(claimed, false, "req.claimed");
        assertEq(claimTimestamp, expectedClaimTimestamp, "req.claimTimestamp");
        assertEq(storedAssets, expectedAssets, "req.assets");
        assertEq(storedQueued, expectedQueued, "req.queued");
        assertEq(storedShares, expectedShares, "req.shares");
    }
}
