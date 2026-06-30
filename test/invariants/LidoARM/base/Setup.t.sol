// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "./Base.t.sol";

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {StETHAssetAdapter} from "contracts/adapters/StETHAssetAdapter.sol";
import {WstETHAssetAdapter} from "contracts/adapters/WstETHAssetAdapter.sol";
import {AbstractLidoAssetAdapter} from "contracts/adapters/AbstractLidoAssetAdapter.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Mocks
import {WETH} from "@solmate/tokens/WETH.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockWstETH} from "../mocks/MockWstETH.sol";
import {MockMorpho} from "../mocks/MockMorpho.sol";
import {MockLidoWithdraw} from "../mocks/MockLidoWithdraw.sol";

// Helpers
import {Helpers} from "../helpers/Helpers.t.sol";

abstract contract Invariant_LidoARM_Setup_Test is Base_Test_, Helpers {
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

        // Ignite
        ignite();
    }

    function deployMockContracts() internal virtual {
        // Deploy tokens
        weth = IERC20(address(new WETH()));
        steth = IERC20(address(new MockERC20("Staked Ether", "stETH", 18)));
        mockWstETH = new MockWstETH(steth);
        wsteth = IERC20(address(mockWstETH));

        // Deploy markets
        mockERC4626Market_A = new MockMorpho(address(weth));
        mockERC4626Market_B = new MockMorpho(address(weth));

        // Deploy Lido withdrawal queue
        lidoWithdrawalQueue = new MockLidoWithdraw(address(steth));
    }

    function deployContracts() internal virtual {
        vm.startPrank(deployer);

        // --- Deploy Proxies
        Proxy lidoARMProxy = new Proxy();
        Proxy stETHAssetAdapterProxy = new Proxy();
        Proxy wstETHAssetAdapterProxy = new Proxy();

        // --- Deploy Logic contracts
        LidoARM lidoARMLogic = new LidoARM({
            _weth: address(weth),
            _claimDelay: CLAIM_DELAY,
            _minSharesToRedeem: MIN_SHARES_TO_REDEEM,
            _allocateThreshold: 1 ether
        });
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

        // Initialization requires 1e15 liquid assets to mint to dead address.
        // Mint 1e15 liquid assets to the deployer.
        deal(address(weth), deployer, 1e15);
        // Deployer approve the proxy to transfer 1e15 liquid assets.
        weth.approve(address(lidoARMProxy), 1e15);

        // --- Initialize Proxies
        // LidoARM Proxy
        lidoARMProxy.initialize(
            address(lidoARMLogic),
            governor,
            abi.encodeWithSelector(
                LidoARM.initialize.selector, "Lido ARM", "LIDO-ARM", operator, DEFAULT_FEE, feeCollector, address(0)
            )
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
        stETHAssetAdapter = StETHAssetAdapter(payable(address(stETHAssetAdapterProxy)));
        wstETHAssetAdapter = WstETHAssetAdapter(payable(address(wstETHAssetAdapterProxy)));
    }

    function labelAll() internal virtual {
        vm.label(address(weth), "WETH");
        vm.label(address(steth), "STETH");
        vm.label(address(wsteth), "WSTETH");
        vm.label(address(mockWstETH), "WSTETH");
        vm.label(address(lidoARM), "LIDO ARM PROXY");
        vm.label(address(stETHAssetAdapter), "STETH ASSET ADAPTER PROXY");
        vm.label(address(wstETHAssetAdapter), "WSTETH ASSET ADAPTER PROXY");
        vm.label(address(lidoWithdrawalQueue), "LIDO WITHDRAWAL QUEUE (MOCK)");
        vm.label(address(mockERC4626Market_A), "ERC4626 MARKET A (MOCK)");
        vm.label(address(mockERC4626Market_B), "ERC4626 MARKET B (MOCK)");
    }

    function approveSpending() internal {
        for (uint256 i = 0; i < users.length; i++) {
            address lp = users[i];
            vm.startPrank(lp);
            weth.approve(address(lidoARM), type(uint256).max);
            steth.approve(address(lidoARM), type(uint256).max);
            wsteth.approve(address(lidoARM), type(uint256).max);
            vm.stopPrank();
        }
        vm.startPrank(hanna);
        weth.approve(address(mockERC4626Market_A), type(uint256).max);
        weth.approve(address(mockERC4626Market_B), type(uint256).max);
        vm.stopPrank();
    }

    function ignite() internal {
        // 1. LP mint 1 ether of shares, to reflect that ARM doesn't start with only liquidity minted to dead address
        deal(address(weth), frank, 1 ether);
        vm.prank(frank);
        lidoARM.deposit(1 ether);
        sum_weth_deposit += 1 ether;
        ghost_userDeposited[frank] = 1 ether;

        // 2. Add stETH and wstETH as Base Assets in the ARM
        vm.prank(governor);
        lidoARM.addBaseAsset({
            newBaseAsset: address(steth),
            adapter: address(stETHAssetAdapter),
            buyPrice: 992 * 1e33,
            sellPrice: 1001 * 1e33,
            buyAmount: type(uint128).max,
            sellAmount: type(uint128).max,
            newCrossPrice: 1e36,
            peggedToLiquidityAsset: true
        });
        vm.prank(governor);
        lidoARM.addBaseAsset({
            newBaseAsset: address(wsteth),
            adapter: address(wstETHAssetAdapter),
            buyPrice: 992 * 1e33,
            sellPrice: 1001 * 1e33,
            buyAmount: type(uint128).max,
            sellAmount: type(uint128).max,
            newCrossPrice: 1e36,
            peggedToLiquidityAsset: false
        });

        // 3. Add markets to the ARM
        address[] memory markets = new address[](2);
        markets[0] = address(mockERC4626Market_A);
        markets[1] = address(mockERC4626Market_B);
        vm.prank(governor);
        lidoARM.addMarkets(markets);

        // 4. Seed wstETH with stETH to simulate a realistic wstETH/stETH exchange rate
        uint256 stEthAmount = 1_000_000 ether;
        MockERC20(address(steth)).mint(address(this), stEthAmount);
        steth.approve(address(mockWstETH), type(uint256).max);
        mockWstETH.wrap(stEthAmount);
        // Simulate 1 wstETH = 1.235 stETH
        MockERC20(address(steth)).mint(address(wsteth), 235_000 ether);
        assertEq(mockWstETH.getStETHByWstETH(1e18), 1.235e18, "Invalid initial wstETH price");

        //5. Ignite markets
        deal(address(weth), address(this), 20_000 ether);
        weth.approve(address(mockERC4626Market_A), type(uint256).max);
        weth.approve(address(mockERC4626Market_B), type(uint256).max);
        mockERC4626Market_A.deposit(10_000 ether, address(this));
        mockERC4626Market_B.deposit(10_000 ether, address(this));
        // Simulate accrued yield in the markets. `deal` overwrites the balance (it does not add), so
        // the target is the 10_000 deposited + the yield. This keeps the share price above 1 (~1.15 /
        // ~1.20) as in a real interest-bearing vault; a price below 1 would let dust shares convert to
        // 0 assets and brick ERC4626.redeem with ZERO_ASSETS.
        deal(address(weth), address(mockERC4626Market_A), 10_000 ether + 1_458 ether);
        deal(address(weth), address(mockERC4626Market_B), 10_000 ether + 1_981 ether);

        // 6. Give LPs initial liquidity
        for (uint256 i; i < LP_COUNT; i++) {
            address lp = lps[i];
            deal(address(weth), lp, INITIAL_LP_LIQUIDITY);
        }

        // 7. Give Morpho supplier initial liquidity
        deal(address(weth), hanna, INITIAL_LP_LIQUIDITY / 10);

        // 8. Initialize share price tracking
        ghost_lastSharePrice = lidoARM.totalAssets() * 1e18 / lidoARM.totalSupply();
    }
}
