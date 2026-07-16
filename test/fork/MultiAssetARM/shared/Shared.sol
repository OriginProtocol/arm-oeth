// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "test/Base.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {StETHAssetAdapter} from "contracts/adapters/StETHAssetAdapter.sol";
import {WstETHAssetAdapter} from "contracts/adapters/WstETHAssetAdapter.sol";
import {EtherFiAssetAdapter} from "contracts/adapters/EtherFiAssetAdapter.sol";
import {WeETHAssetAdapter} from "contracts/adapters/WeETHAssetAdapter.sol";
import {AbstractLidoAssetAdapter} from "contracts/adapters/AbstractLidoAssetAdapter.sol";

// Interfaces
import {Mainnet} from "src/contracts/utils/Addresses.sol";
import {IERC20, IAssetAdapter, IEETHWithdrawalNFT} from "contracts/Interfaces.sol";

/// @notice Minimal view of the Lido withdrawal queue's finalize path. `IStETHWithdrawal` in
///         Interfaces.sol only declares request/claim, so the fork finalization helper declares
///         the extra functions it needs here. `finalize` is gated by Lido's FINALIZE_ROLE, which
///         is held by the stETH contract — see {Fork_Shared_Test-_finalizeLido}.
interface ILidoFinalize {
    function finalize(uint256 _lastRequestIdToBeFinalized, uint256 _maxShareRate) external payable;
    function getLastRequestId() external view returns (uint256);
    function unfinalizedStETH() external view returns (uint256);
}

/// @notice Getters shared by every asset adapter's pending-request queue (Lido and EtherFi). Lets the
///         request/claim tests inspect queue state without importing each concrete adapter type.
interface IAdapterQueue {
    function pendingRequestIdsLength() external view returns (uint256);
    function pendingRequestId(uint256 index) external view returns (uint256);
    function requestShares(uint256 requestId) external view returns (uint256);
}

/// @notice Minimal EtherFi liquidity-pool interface used to acquire backed eETH on a fork.
interface IEtherFiLiquidityPool {
    function deposit() external payable returns (uint256);
}

/// @notice Shared fork setup for the MultiAssetARM suite. Deploys a single MultiAssetARM (WETH
///         liquidity) with the four Lido/EtherFi base assets and their adapters wired to the real
///         mainnet protocol contracts. Mirrors the structure of test/fork/EthenaARM/shared/Shared.sol.
abstract contract Fork_Shared_Test is Base_Test_ {
    /// @notice EtherFi WithdrawRequestNFT admin able to finalize requests on a mainnet fork.
    address public constant ETHERFI_WITHDRAW_ADMIN = 0x0EF8fa4760Db8f5Cd4d993f3e3416f30f942D705;

    /// @notice Generous Lido share-rate cap (1e27 == 1:1) so finalized requests pay out in full.
    uint256 public constant LIDO_MAX_SHARE_RATE = 1.5e27;

    MultiAssetARM public arm;
    StETHAssetAdapter public stethAssetAdapter;
    WstETHAssetAdapter public wstethAssetAdapter;
    WeETHAssetAdapter public weethAssetAdapter;

    // `etherfiAssetAdapter` (EtherFiAssetAdapter) is declared in Base_Test_ and reused here.

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();

        _createAndSelectFork();
        _deployMockContracts();
        _generateAddresses();
        _deployContracts();
        _ignite();
        labelAll();
    }

    function _createAndSelectFork() internal {
        require(vm.envExists("MAINNET_URL"), "MAINNET_URL not set");

        if (vm.envExists("FORK_BLOCK_NUMBER_MAINNET")) {
            vm.createSelectFork("mainnet", vm.envUint("FORK_BLOCK_NUMBER_MAINNET"));
        } else {
            vm.createSelectFork("mainnet");
        }
    }

    function _deployMockContracts() internal {
        weth = IERC20(Mainnet.WETH);
        steth = IERC20(Mainnet.STETH);
        wsteth = IERC20(Mainnet.WSTETH);
        eeth = IERC20(Mainnet.EETH);
        weeth = IERC20(Mainnet.WEETH);
        badToken = IERC20(address(0xDEADBEEF));
    }

    function _generateAddresses() internal {
        governor = makeAddr("governor");
        deployer = makeAddr("deployer");
        operator = makeAddr("operator");
        feeCollector = makeAddr("feeCollector");
    }

    function _deployContracts() internal {
        vm.startPrank(deployer);

        // 1. Deploy the MultiAssetARM behind a proxy (WETH liquidity asset).
        MultiAssetARM armImpl = new MultiAssetARM({
            _liquidityAsset: address(weth),
            _claimDelay: 10 minutes,
            _minSharesToRedeem: 1e7,
            _allocateThreshold: 1 ether
        });
        Proxy armProxy = new Proxy();

        // Initialization mints MIN_TOTAL_SUPPLY to the dead address against MIN_LIQUIDITY (1e12) WETH.
        deal(address(weth), deployer, 1e12);
        weth.approve(address(armProxy), 1e12);

        armProxy.initialize(
            address(armImpl),
            governor,
            abi.encodeWithSelector(
                MultiAssetARM.initialize.selector,
                "Ether ARM",
                "ARM-WETH",
                operator,
                2000, // 20% performance fee
                feeCollector,
                address(0) // no cap manager
            )
        );
        arm = MultiAssetARM(payable(address(armProxy)));
        vm.stopPrank();

        // 2. Deploy the four asset adapters, each behind a proxy. Initialize through the proxy so the
        //    token approvals to the withdrawal queues are set on the proxy's storage.
        stethAssetAdapter = StETHAssetAdapter(
            payable(_deployAdapter(
                    address(new StETHAssetAdapter(address(arm), address(weth), address(steth), Mainnet.LIDO_WITHDRAWAL))
                ))
        );
        wstethAssetAdapter = WstETHAssetAdapter(
            payable(_deployAdapter(
                    address(
                        new WstETHAssetAdapter(
                            address(arm), address(weth), address(steth), address(wsteth), Mainnet.LIDO_WITHDRAWAL
                        )
                    )
                ))
        );
        etherfiAssetAdapter = EtherFiAssetAdapter(
            payable(_deployAdapter(
                    address(
                        new EtherFiAssetAdapter(
                            address(arm),
                            address(eeth),
                            address(weth),
                            Mainnet.ETHERFI_WITHDRAWAL,
                            Mainnet.ETHERFI_WITHDRAWAL_NFT
                        )
                    )
                ))
        );
        weethAssetAdapter = WeETHAssetAdapter(
            payable(_deployAdapter(
                    address(
                        new WeETHAssetAdapter(
                            address(arm),
                            address(weeth),
                            address(eeth),
                            address(weth),
                            Mainnet.ETHERFI_WITHDRAWAL,
                            Mainnet.ETHERFI_WITHDRAWAL_NFT
                        )
                    )
                ))
        );
    }

    /// @notice Deploys an adapter proxy and runs its `initialize()` (selector shared across adapters).
    function _deployAdapter(address impl) internal returns (address proxy) {
        vm.startPrank(deployer);
        Proxy adapterProxy = new Proxy();
        adapterProxy.initialize(impl, governor, abi.encodeWithSelector(AbstractLidoAssetAdapter.initialize.selector));
        vm.stopPrank();
        proxy = address(adapterProxy);
    }

    function _ignite() internal virtual {
        // Fund the test contract with WETH and deposit liquidity into the ARM.
        deal(address(weth), address(this), 1_000_000 ether);
        weth.approve(address(arm), type(uint256).max);
        arm.deposit(10_000 ether);

        // Register the four base assets. Prices mirror the adapter unit tests: a 0.992 buy / 1.001 sell
        // band around a 1.0 cross. stETH/eETH are pegged 1:1 (swaps skip the adapter); wstETH/weETH are
        // not pegged so swaps value them through the wrapper exchange rate.
        vm.startPrank(arm.owner());
        arm.addBaseAsset(
            address(steth),
            address(stethAssetAdapter),
            0.992e36,
            1.001e36,
            type(uint128).max,
            type(uint128).max,
            1e36,
            true
        );
        arm.addBaseAsset(
            address(wsteth),
            address(wstethAssetAdapter),
            0.992e36,
            1.001e36,
            type(uint128).max,
            type(uint128).max,
            1e36,
            false
        );
        arm.addBaseAsset(
            address(eeth),
            address(etherfiAssetAdapter),
            0.992e36,
            1.001e36,
            type(uint128).max,
            type(uint128).max,
            1e36,
            true
        );
        arm.addBaseAsset(
            address(weeth),
            address(weethAssetAdapter),
            0.992e36,
            1.001e36,
            type(uint128).max,
            type(uint128).max,
            1e36,
            false
        );
        vm.stopPrank();

        // Seed base-asset inventory on the ARM (so it can sell base assets to traders) and on the test
        // contract (so it can sell base assets back to the ARM).
        _seedAsset(steth);
        _seedAsset(wsteth);
        _seedAsset(eeth);
        _seedAsset(weeth);
    }

    function _seedAsset(IERC20 token) internal {
        deal(address(token), address(arm), 5_000 ether);
        deal(address(token), address(this), 5_000 ether);
        token.approve(address(arm), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- TOKEN ACQUISITION (rebasing tokens cannot use `deal` directly)
    //////////////////////////////////////////////////////
    /// @notice stETH and eETH are rebasing share tokens, so editing their balance slot breaks accounting.
    ///         Acquire stETH from the wstETH wrapper and mint fully backed eETH through EtherFi's liquidity
    ///         pool. Taking eETH from the weETH wrapper would leave it underbacked and make unwrap revert.
    ///         wstETH/weETH/WETH are plain ERC20s and use the default deal.
    function deal(address token, address to, uint256 amount) internal override {
        if (token == address(steth)) {
            vm.prank(address(wsteth));
            steth.transfer(to, amount);
        } else if (token == address(eeth)) {
            uint256 depositAmount = amount + 1 ether;
            vm.deal(address(this), address(this).balance + depositAmount);
            IEtherFiLiquidityPool(Mainnet.ETHERFI_LIQUIDITY_POOL).deposit{value: depositAmount}();
            eeth.transfer(to, amount);
        } else {
            super.deal(token, to, amount);
        }
    }

    //////////////////////////////////////////////////////
    /// --- PRICE / CONFIG HELPERS
    //////////////////////////////////////////////////////
    function _buyPrice(IERC20 token) internal view returns (uint256 buyPrice) {
        (uint128 _buy,,,,,,,,) = arm.baseAssetConfigs(address(token));
        buyPrice = _buy;
    }

    function _sellPrice(IERC20 token) internal view returns (uint256 sellPrice) {
        (, uint128 _sell,,,,,,,) = arm.baseAssetConfigs(address(token));
        sellPrice = _sell;
    }

    function _crossPrice(IERC20 token) internal view returns (uint256 crossPrice) {
        (,,,, uint128 _cross,,,,) = arm.baseAssetConfigs(address(token));
        crossPrice = _cross;
    }

    function _pendingRedeemAssets(IERC20 token) internal view returns (uint256 pending) {
        (,,,,, uint128 _pending,,,) = arm.baseAssetConfigs(address(token));
        pending = _pending;
    }

    function _adapter(IERC20 token) internal view returns (IAssetAdapter) {
        (,,,,,,,, address adapter) = arm.baseAssetConfigs(address(token));
        return IAssetAdapter(adapter);
    }

    function _queue(IERC20 token) internal view returns (IAdapterQueue) {
        return IAdapterQueue(address(_adapter(token)));
    }

    /// @notice Liquidity-asset value of `shares` base asset, as the ARM prices it (1:1 for pegged
    ///         stETH/eETH, wrapper rate for wstETH/weETH). Used on the buy side.
    function _convertToAssets(IERC20 token, uint256 shares) internal view returns (uint256) {
        return _adapter(token).convertToAssets(shares);
    }

    /// @notice Base-asset value of `assets` liquidity, as the ARM prices it. Used on the sell side.
    function _convertToShares(IERC20 token, uint256 assets) internal view returns (uint256) {
        return _adapter(token).convertToShares(assets);
    }

    function _swapFeeMultiplier(uint256 buyPrice, uint256 crossPrice, uint256 fee) internal pure returns (uint256) {
        if (buyPrice == 0 || fee == 0) return 0;
        return (crossPrice - buyPrice) * fee * PRICE_SCALE / (buyPrice * FEE_SCALE);
    }

    //////////////////////////////////////////////////////
    /// --- WITHDRAWAL FINALIZATION (real protocol finalization on the fork)
    //////////////////////////////////////////////////////
    /// @notice Finalizes every outstanding Lido withdrawal request (the real backlog plus the ones
    ///         opened by the test) in a single checkpoint. The FINALIZE_ROLE is held by the stETH
    ///         contract, so we impersonate it and fund the call with the full unfinalized stETH amount.
    function _finalizeLido() internal {
        ILidoFinalize queue = ILidoFinalize(Mainnet.LIDO_WITHDRAWAL);
        // Resolve every read before pranking: argument calls evaluate after vm.prank and would
        // otherwise consume it, leaving `finalize` to run unpranked.
        uint256 lastRequestId = queue.getLastRequestId();
        uint256 ethToLock = queue.unfinalizedStETH();
        vm.deal(Mainnet.STETH, Mainnet.STETH.balance + ethToLock);
        vm.prank(Mainnet.STETH);
        queue.finalize{value: ethToLock}(lastRequestId, LIDO_MAX_SHARE_RATE);
    }

    /// @notice Finalizes EtherFi withdrawal requests up to and including `requestId` via the NFT admin.
    /// @dev The current EtherFi implementation requires finalized withdrawal ETH to be transferred from
    ///      the liquidity pool into the withdrawal NFT's segregated escrow. Older implementations paid
    ///      claims directly from the liquidity pool, so only fund the escrow when its getter is available.
    function _finalizeEtherFi(uint256 requestId, uint256 assetsExpected) internal {
        vm.deal(Mainnet.ETHERFI_LIQUIDITY_POOL, Mainnet.ETHERFI_LIQUIDITY_POOL.balance + assetsExpected);

        (bool usesEscrow,) =
            Mainnet.ETHERFI_WITHDRAWAL_NFT.staticcall(abi.encodeWithSignature("ethAmountLockedForWithdrawal()"));
        if (usesEscrow) {
            vm.prank(Mainnet.ETHERFI_LIQUIDITY_POOL);
            (bool funded,) = payable(Mainnet.ETHERFI_WITHDRAWAL_NFT).call{value: assetsExpected}("");
            require(funded, "EtherFi escrow funding failed");
        }

        vm.prank(ETHERFI_WITHDRAW_ADMIN);
        IEETHWithdrawalNFT(Mainnet.ETHERFI_WITHDRAWAL_NFT).finalizeRequests(requestId);
    }
}
