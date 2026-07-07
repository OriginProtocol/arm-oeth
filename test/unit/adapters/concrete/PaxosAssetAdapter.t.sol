// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Test} from "forge-std/Test.sol";

// Contracts
import {PaxosAssetAdapter} from "contracts/adapters/PaxosAssetAdapter.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Ownable} from "contracts/Ownable.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";

// External
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

/// @notice Unit tests for `PaxosAssetAdapter`. The adapter queues Paxos-issued stablecoins (e.g. PYUSD)
///         pulled from the ARM (`pendingShares`), forwards them to a Paxos deposit address
///         (`settlingShares`), and later hands settled USDC back to the ARM 1:1. Paxos settlement is
///         simulated by minting USDC directly to the adapter. Deployed behind a `Proxy` because the
///         implementation constructor renounces ownership. The ARM is a plain pranked address.
contract Unit_PaxosAssetAdapter_Test is Test {
    PaxosAssetAdapter internal adapter;
    MockERC20 internal pyusd;
    MockERC20 internal usdc;

    address internal arm = makeAddr("arm");
    address internal governor = makeAddr("governor");
    address internal operator = makeAddr("operator");
    address internal alice = makeAddr("alice");
    address internal paxosRecipient = makeAddr("paxosRecipient");

    uint256 internal constant ARM_PYUSD_BALANCE = 5_000e6;

    event PaxosRecipientUpdated(address indexed paxosRecipient);
    event PaxosRedeemSubmitted(bytes32 indexed paxosRedemptionId, uint256 shares, address indexed paxosRecipient);
    event ExcessLiquidityRecovered(address indexed to, uint256 amount);

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        pyusd = new MockERC20("PayPal USD", "PYUSD", 6);

        adapter = _deployAdapter(paxosRecipient);

        // Seed the ARM with PYUSD and approve the adapter (proxy) to pull it.
        pyusd.mint(arm, ARM_PYUSD_BALANCE);
        vm.prank(arm);
        pyusd.approve(address(adapter), type(uint256).max);
    }

    /// @dev Deploys the adapter behind a proxy owned by `governor` and initialized with `operator`.
    function _deployAdapter(address _paxosRecipient) internal returns (PaxosAssetAdapter) {
        PaxosAssetAdapter impl = new PaxosAssetAdapter(arm, address(pyusd), address(usdc));
        Proxy proxy = new Proxy();
        proxy.initialize(
            address(impl),
            governor,
            abi.encodeWithSelector(PaxosAssetAdapter.initialize.selector, operator, _paxosRecipient)
        );
        return PaxosAssetAdapter(address(proxy));
    }

    //////////////////////////////////////////////////////
    /// --- constructor
    //////////////////////////////////////////////////////
    function test_Constructor_SetsImmutables() public {
        PaxosAssetAdapter impl = new PaxosAssetAdapter(arm, address(pyusd), address(usdc));

        assertEq(impl.arm(), arm, "arm");
        assertEq(address(impl.baseAsset()), address(pyusd), "baseAsset");
        assertEq(address(impl.liquidityAsset()), address(usdc), "liquidityAsset");
        // Implementation ownership is renounced so it can only be used behind a proxy.
        assertEq(impl.owner(), address(0), "impl owner renounced");
    }

    function test_Constructor_RevertWhen_DecimalsMismatch() public {
        MockERC20 dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        vm.expectRevert(PaxosAssetAdapter.DecimalsMismatch.selector);
        new PaxosAssetAdapter(arm, address(pyusd), address(dai));
    }

    function test_Constructor_DisablesInitializers() public {
        PaxosAssetAdapter impl = new PaxosAssetAdapter(arm, address(pyusd), address(usdc));

        // The bare implementation can never be initialized; only proxies can.
        vm.expectRevert(); // OZ Initializable: InvalidInitialization
        impl.initialize(operator, paxosRecipient);
    }

    //////////////////////////////////////////////////////
    /// --- initialize
    //////////////////////////////////////////////////////
    function test_Initialize_SetsOperatorAndPaxosRecipient() public {
        PaxosAssetAdapter impl = new PaxosAssetAdapter(arm, address(pyusd), address(usdc));
        Proxy proxy = new Proxy();

        vm.expectEmit(true, false, false, true);
        emit PaxosRecipientUpdated(paxosRecipient);
        proxy.initialize(
            address(impl),
            governor,
            abi.encodeWithSelector(PaxosAssetAdapter.initialize.selector, operator, paxosRecipient)
        );

        PaxosAssetAdapter fresh = PaxosAssetAdapter(address(proxy));
        assertEq(fresh.operator(), operator, "operator");
        assertEq(fresh.paxosRecipient(), paxosRecipient, "paxosRecipient");
        assertEq(fresh.owner(), governor, "proxy owner");
    }

    function test_Initialize_ZeroRecipient_LeavesRecipientUnset() public {
        PaxosAssetAdapter bare = _deployAdapter(address(0));

        assertEq(bare.operator(), operator, "operator");
        assertEq(bare.paxosRecipient(), address(0), "paxosRecipient unset");
    }

    function test_Initialize_RevertWhen_CalledTwice() public {
        vm.expectRevert(); // OZ Initializable: InvalidInitialization
        adapter.initialize(operator, paxosRecipient);
    }

    //////////////////////////////////////////////////////
    /// --- view / conversions
    //////////////////////////////////////////////////////
    function test_Asset_ReturnsLiquidityAsset() public view {
        assertEq(adapter.asset(), address(usdc), "asset");
    }

    function test_ConvertToAssets_OneToOne() public view {
        assertEq(adapter.convertToAssets(0), 0, "zero");
        assertEq(adapter.convertToAssets(100e6), 100e6, "100 PYUSD");
        assertEq(adapter.convertToAssets(type(uint256).max), type(uint256).max, "max");
    }

    function test_ConvertToShares_OneToOne() public view {
        assertEq(adapter.convertToShares(0), 0, "zero");
        assertEq(adapter.convertToShares(100e6), 100e6, "100 USDC");
        assertEq(adapter.convertToShares(type(uint256).max), type(uint256).max, "max");
    }

    //////////////////////////////////////////////////////
    /// --- modifiers / access control
    //////////////////////////////////////////////////////
    function test_RequestRedeem_RevertWhen_NotARM() public {
        vm.prank(alice);
        vm.expectRevert(PaxosAssetAdapter.OnlyARM.selector);
        adapter.requestRedeem(100e6);
    }

    function test_RequestRedeem_RevertWhen_ZeroShares() public {
        vm.prank(arm);
        vm.expectRevert(PaxosAssetAdapter.ZeroShares.selector);
        adapter.requestRedeem(0);
    }

    function test_Redeem_RevertWhen_NotARM() public {
        vm.prank(alice);
        vm.expectRevert(PaxosAssetAdapter.OnlyARM.selector);
        adapter.redeem(100e6);
    }

    function test_Redeem_RevertWhen_ZeroShares() public {
        vm.prank(arm);
        vm.expectRevert(PaxosAssetAdapter.ZeroShares.selector);
        adapter.redeem(0);
    }

    function test_SubmitPaxosRedeem_RevertWhen_NotOperatorOrOwner() public {
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        adapter.submitPaxosRedeem(100e6, bytes32("id"));
    }

    function test_SubmitPaxosRedeem_RevertWhen_ZeroShares() public {
        vm.prank(operator);
        vm.expectRevert(PaxosAssetAdapter.ZeroShares.selector);
        adapter.submitPaxosRedeem(0, bytes32("id"));
    }

    function test_SetPaxosRecipient_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        adapter.setPaxosRecipient(alice);

        // The operator cannot set the recipient either.
        vm.prank(operator);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        adapter.setPaxosRecipient(alice);
    }

    function test_SetPaxosRecipient_RevertWhen_ZeroAddress() public {
        vm.prank(governor);
        vm.expectRevert(PaxosAssetAdapter.InvalidPaxosRecipient.selector);
        adapter.setPaxosRecipient(address(0));
    }

    function test_SetPaxosRecipient_UpdatesAndEmits() public {
        address newRecipient = makeAddr("newRecipient");

        vm.expectEmit(true, false, false, true, address(adapter));
        emit PaxosRecipientUpdated(newRecipient);
        vm.prank(governor);
        adapter.setPaxosRecipient(newRecipient);

        assertEq(adapter.paxosRecipient(), newRecipient, "paxosRecipient updated");
    }

    //////////////////////////////////////////////////////
    /// --- requestRedeem
    //////////////////////////////////////////////////////
    function test_RequestRedeem_PullsBaseAssetAndTracksPending() public {
        uint256 shares = 500e6;

        vm.prank(arm);
        (uint256 sharesRequested, uint256 assetsExpected) = adapter.requestRedeem(shares);

        assertEq(sharesRequested, shares, "sharesRequested");
        assertEq(assetsExpected, shares, "assetsExpected (1:1)");

        // PYUSD moved from the ARM into the adapter.
        assertEq(pyusd.balanceOf(arm), ARM_PYUSD_BALANCE - shares, "ARM PYUSD post");
        assertEq(pyusd.balanceOf(address(adapter)), shares, "adapter PYUSD post");

        // Adapter bookkeeping.
        assertEq(adapter.pendingShares(), shares, "pendingShares");
        assertEq(adapter.settlingShares(), 0, "settlingShares untouched");
    }

    function test_RequestRedeem_AccumulatesAcrossRequests() public {
        vm.prank(arm);
        adapter.requestRedeem(300e6);
        vm.prank(arm);
        adapter.requestRedeem(200e6);

        assertEq(adapter.pendingShares(), 500e6, "pendingShares accumulated");
        assertEq(pyusd.balanceOf(address(adapter)), 500e6, "adapter PYUSD post");
        assertEq(pyusd.balanceOf(arm), ARM_PYUSD_BALANCE - 500e6, "ARM PYUSD post");
    }

    //////////////////////////////////////////////////////
    /// --- submitPaxosRedeem
    //////////////////////////////////////////////////////
    function test_SubmitPaxosRedeem_MovesPendingToSettling() public {
        uint256 shares = 500e6;
        bytes32 redemptionId = keccak256("paxos-redemption-1");

        vm.prank(arm);
        adapter.requestRedeem(shares);

        vm.expectEmit(true, true, false, true, address(adapter));
        emit PaxosRedeemSubmitted(redemptionId, shares, paxosRecipient);
        vm.prank(operator);
        adapter.submitPaxosRedeem(shares, redemptionId);

        // PYUSD forwarded to the Paxos deposit address.
        assertEq(pyusd.balanceOf(paxosRecipient), shares, "recipient PYUSD post");
        assertEq(pyusd.balanceOf(address(adapter)), 0, "adapter PYUSD post");

        // pending -> settling.
        assertEq(adapter.pendingShares(), 0, "pendingShares cleared");
        assertEq(adapter.settlingShares(), shares, "settlingShares");
    }

    function test_SubmitPaxosRedeem_PartialAmount() public {
        vm.prank(arm);
        adapter.requestRedeem(500e6);

        vm.prank(operator);
        adapter.submitPaxosRedeem(200e6, bytes32("id"));

        assertEq(adapter.pendingShares(), 300e6, "pendingShares remainder");
        assertEq(adapter.settlingShares(), 200e6, "settlingShares");
        assertEq(pyusd.balanceOf(paxosRecipient), 200e6, "recipient PYUSD post");
        assertEq(pyusd.balanceOf(address(adapter)), 300e6, "adapter PYUSD post");
    }

    function test_SubmitPaxosRedeem_CallableByOwner() public {
        vm.prank(arm);
        adapter.requestRedeem(100e6);

        vm.prank(governor);
        adapter.submitPaxosRedeem(100e6, bytes32("id"));

        assertEq(adapter.settlingShares(), 100e6, "settlingShares");
        assertEq(pyusd.balanceOf(paxosRecipient), 100e6, "recipient PYUSD post");
    }

    function test_SubmitPaxosRedeem_RevertWhen_ExceedsPending() public {
        vm.prank(arm);
        adapter.requestRedeem(100e6);

        vm.prank(operator);
        vm.expectRevert(PaxosAssetAdapter.RedeemAmountTooHigh.selector);
        adapter.submitPaxosRedeem(100e6 + 1, bytes32("id"));
    }

    function test_SubmitPaxosRedeem_RevertWhen_RecipientNotConfigured() public {
        PaxosAssetAdapter bare = _deployAdapter(address(0));
        pyusd.mint(arm, 100e6);
        vm.prank(arm);
        pyusd.approve(address(bare), type(uint256).max);

        vm.prank(arm);
        bare.requestRedeem(100e6);

        vm.prank(operator);
        vm.expectRevert(PaxosAssetAdapter.PaxosRecipientNotConfigured.selector);
        bare.submitPaxosRedeem(100e6, bytes32("id"));
    }

    //////////////////////////////////////////////////////
    /// --- redeem
    //////////////////////////////////////////////////////
    function test_Redeem_TransfersSettledUsdcToARM() public {
        uint256 shares = 500e6;

        vm.prank(arm);
        adapter.requestRedeem(shares);
        vm.prank(operator);
        adapter.submitPaxosRedeem(shares, bytes32("id"));
        // Simulate Paxos settling USDC 1:1 to the adapter.
        usdc.mint(address(adapter), shares);

        vm.prank(arm);
        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) = adapter.redeem(shares);

        assertEq(sharesClaimed, shares, "sharesClaimed");
        assertEq(assetsExpected, shares, "assetsExpected");
        assertEq(assetsReceived, shares, "assetsReceived");

        // USDC lands on the ARM; adapter holds none.
        assertEq(usdc.balanceOf(arm), shares, "ARM USDC post");
        assertEq(usdc.balanceOf(address(adapter)), 0, "adapter USDC post");
        assertEq(adapter.settlingShares(), 0, "settlingShares cleared");
    }

    function test_Redeem_PartialAmount() public {
        vm.prank(arm);
        adapter.requestRedeem(500e6);
        vm.prank(operator);
        adapter.submitPaxosRedeem(500e6, bytes32("id"));
        usdc.mint(address(adapter), 500e6);

        vm.prank(arm);
        adapter.redeem(200e6);

        assertEq(adapter.settlingShares(), 300e6, "settlingShares remainder");
        assertEq(usdc.balanceOf(arm), 200e6, "ARM USDC post");
        assertEq(usdc.balanceOf(address(adapter)), 300e6, "adapter USDC post");
    }

    function test_Redeem_RevertWhen_ExceedsSettling() public {
        vm.prank(arm);
        adapter.requestRedeem(100e6);
        vm.prank(operator);
        adapter.submitPaxosRedeem(100e6, bytes32("id"));
        usdc.mint(address(adapter), 200e6);

        // More USDC than settling shares is available, but the settling cap still binds.
        vm.prank(arm);
        vm.expectRevert(PaxosAssetAdapter.RedeemAmountTooHigh.selector);
        adapter.redeem(100e6 + 1);
    }

    function test_Redeem_RevertWhen_InsufficientSettledAssets() public {
        vm.prank(arm);
        adapter.requestRedeem(500e6);
        vm.prank(operator);
        adapter.submitPaxosRedeem(500e6, bytes32("id"));
        // Paxos has only settled part of the redemption so far.
        usdc.mint(address(adapter), 300e6);

        vm.prank(arm);
        vm.expectRevert(abi.encodeWithSelector(PaxosAssetAdapter.InsufficientSettledAssets.selector, 500e6, 300e6));
        adapter.redeem(500e6);
    }

    //////////////////////////////////////////////////////
    /// --- lifecycle
    //////////////////////////////////////////////////////
    function test_Lifecycle_FullFlow() public {
        uint256 shares = 500e6;

        // 1. ARM queues PYUSD for redemption.
        vm.prank(arm);
        adapter.requestRedeem(shares);

        // 2. Operator submits the queued PYUSD to Paxos.
        vm.prank(operator);
        adapter.submitPaxosRedeem(shares, bytes32("id"));

        // 3. Paxos settles USDC 1:1 to the adapter.
        usdc.mint(address(adapter), shares);

        // 4. ARM claims the settled USDC.
        vm.prank(arm);
        adapter.redeem(shares);

        assertEq(adapter.pendingShares(), 0, "pendingShares cleared");
        assertEq(adapter.settlingShares(), 0, "settlingShares cleared");
        assertEq(pyusd.balanceOf(arm), ARM_PYUSD_BALANCE - shares, "ARM PYUSD post");
        assertEq(pyusd.balanceOf(paxosRecipient), shares, "recipient PYUSD post");
        assertEq(pyusd.balanceOf(address(adapter)), 0, "adapter PYUSD post");
        assertEq(usdc.balanceOf(arm), shares, "ARM USDC post");
        assertEq(usdc.balanceOf(address(adapter)), 0, "adapter USDC post");
    }

    function test_Lifecycle_PartialFlow() public {
        // Queue 300, submit only 200 to Paxos.
        vm.prank(arm);
        adapter.requestRedeem(300e6);
        vm.prank(operator);
        adapter.submitPaxosRedeem(200e6, bytes32("id"));

        // Paxos settles the first 150; ARM claims it.
        usdc.mint(address(adapter), 150e6);
        vm.prank(arm);
        adapter.redeem(150e6);

        assertEq(adapter.settlingShares(), 50e6, "settlingShares after first claim");

        // The remaining 50 settling shares are not claimable until USDC arrives.
        vm.prank(arm);
        vm.expectRevert(abi.encodeWithSelector(PaxosAssetAdapter.InsufficientSettledAssets.selector, 50e6, 0));
        adapter.redeem(50e6);

        // Paxos settles the rest; ARM claims it.
        usdc.mint(address(adapter), 50e6);
        vm.prank(arm);
        adapter.redeem(50e6);

        // 100 PYUSD is still queued in the adapter, nothing left settling.
        assertEq(adapter.pendingShares(), 100e6, "pendingShares remainder");
        assertEq(adapter.settlingShares(), 0, "settlingShares cleared");
        assertEq(pyusd.balanceOf(address(adapter)), 100e6, "adapter PYUSD post");
        assertEq(pyusd.balanceOf(paxosRecipient), 200e6, "recipient PYUSD post");
        assertEq(usdc.balanceOf(arm), 200e6, "ARM USDC post");
        assertEq(usdc.balanceOf(address(adapter)), 0, "adapter USDC post");
    }

    //////////////////////////////////////////////////////
    /// --- recoverExcessLiquidity
    //////////////////////////////////////////////////////
    function test_RecoverExcessLiquidity_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        adapter.recoverExcessLiquidity();
    }

    function test_RecoverExcessLiquidity_TransfersOnlyBalanceAboveSettlingShares() public {
        vm.prank(arm);
        adapter.requestRedeem(300e6);
        vm.prank(operator);
        adapter.submitPaxosRedeem(300e6, bytes32("id"));

        // Paxos settles the full amount owed, plus an extra donation/over-settlement.
        usdc.mint(address(adapter), 300e6 + 40e6);

        vm.expectEmit(true, false, false, true, address(adapter));
        emit ExcessLiquidityRecovered(arm, 40e6);
        vm.prank(governor);
        adapter.recoverExcessLiquidity();

        assertEq(usdc.balanceOf(arm), 40e6, "only the excess is recovered");
        assertEq(usdc.balanceOf(address(adapter)), 300e6, "settlingShares-backed balance untouched");
        assertEq(adapter.settlingShares(), 300e6, "settlingShares unchanged");
    }

    function test_RecoverExcessLiquidity_NoExcess_TransfersNothing() public {
        vm.prank(arm);
        adapter.requestRedeem(100e6);
        vm.prank(operator);
        adapter.submitPaxosRedeem(100e6, bytes32("id"));
        usdc.mint(address(adapter), 100e6);

        vm.prank(governor);
        adapter.recoverExcessLiquidity();

        assertEq(usdc.balanceOf(arm), 0, "nothing to recover");
        assertEq(usdc.balanceOf(address(adapter)), 100e6, "adapter balance untouched");
    }
}
