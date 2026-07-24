// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Test} from "forge-std/Test.sol";

// Contracts
import {WeETHAssetAdapter} from "contracts/adapters/WeETHAssetAdapter.sol";

// External
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {WETH} from "@solmate/tokens/WETH.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

// Mocks
import {MockEtherFiWithdraw} from "../mocks/MockEtherFiWithdraw.sol";
import {MockWeETH} from "../mocks/MockWeETH.sol";

/// @notice Unit tests for `WeETHAssetAdapter`. weETH is unwrapped into eETH before opening an Ether.fi
///         withdrawal request, so the adapter tracks both weETH shares and the expected eETH/WETH assets.
///         Driven directly by pranking the ARM address.
contract Unit_WeETHAssetAdapter_Test is Test {
    WeETHAssetAdapter internal adapter;
    MockEtherFiWithdraw internal etherfi;
    MockWeETH internal weeth;
    WETH internal weth;
    MockERC20 internal eeth;

    address internal arm = makeAddr("arm");
    address internal alice = makeAddr("alice");

    uint256 internal constant ARM_WEETH_BALANCE = 5_000 ether;

    function setUp() public {
        weth = new WETH();
        eeth = new MockERC20("Ether.fi ETH", "eETH", 18);
        weeth = new MockWeETH(address(eeth));
        etherfi = new MockEtherFiWithdraw(address(eeth));

        adapter = new WeETHAssetAdapter(
            arm, address(weeth), address(eeth), address(weth), address(etherfi), address(etherfi)
        );
        adapter.initialize();

        // Fund the queue with ETH so claims can pay out, and seed the ARM with weETH.
        vm.deal(address(etherfi), 100_000 ether);
        weeth.mint(arm, ARM_WEETH_BALANCE);
        vm.prank(arm);
        weeth.approve(address(adapter), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- initialize / view / approvals / conversions
    //////////////////////////////////////////////////////
    function test_Initialize_RevertWhen_AlreadyInitialized() public {
        vm.expectRevert(); // OZ Initializable: InvalidInitialization
        adapter.initialize();
    }

    function test_Asset_ReturnsWeth() public view {
        assertEq(adapter.asset(), address(weth), "asset");
    }

    function test_EethApprovalToQueueIsMax() public view {
        assertEq(
            eeth.allowance(address(adapter), address(etherfi)), type(uint256).max, "eETH allowance adapter -> queue"
        );
    }

    function test_ConvertToAssets_DelegatesToWrapper() public {
        weeth.setRate(1.2e18); // 1 weETH = 1.2 eETH
        assertEq(adapter.convertToAssets(100 ether), weeth.getEETHByWeETH(100 ether), "convertToAssets delegates");
        assertEq(adapter.convertToAssets(100 ether), 120 ether, "convertToAssets value");
    }

    function test_ConvertToShares_DelegatesToWrapper() public {
        weeth.setRate(1.25e18); // 1 weETH = 1.25 eETH
        assertEq(adapter.convertToShares(125 ether), weeth.getWeETHByeETH(125 ether), "convertToShares delegates");
        assertEq(adapter.convertToShares(125 ether), 100 ether, "convertToShares value");
    }

    //////////////////////////////////////////////////////
    /// --- modifiers
    //////////////////////////////////////////////////////
    function test_RequestRedeem_RevertWhen_NotARM() public {
        vm.prank(alice);
        vm.expectRevert("Adapter: only ARM");
        adapter.requestRedeem(1 ether);
    }

    function test_RequestRedeem_RevertWhen_ZeroShares() public {
        vm.prank(arm);
        vm.expectRevert("Adapter: zero shares");
        adapter.requestRedeem(0);
    }

    function test_Redeem_RevertWhen_NotARM() public {
        vm.prank(alice);
        vm.expectRevert("Adapter: only ARM");
        adapter.redeem(1 ether);
    }

    function test_Redeem_RevertWhen_ZeroShares() public {
        vm.prank(arm);
        vm.expectRevert("Adapter: zero shares");
        adapter.redeem(0);
    }

    //////////////////////////////////////////////////////
    /// --- requestRedeem
    //////////////////////////////////////////////////////
    function test_RequestRedeem_OneToOne() public {
        uint256 shares = 500 ether;

        vm.prank(arm);
        (uint256 sharesRequested, uint256 assetsExpected) = adapter.requestRedeem(shares);

        assertEq(sharesRequested, shares, "sharesRequested");
        assertEq(assetsExpected, shares, "assetsExpected (1:1 unwrap)");

        // weETH left the ARM; the unwrapped eETH sits in the queue, not the adapter.
        assertEq(weeth.balanceOf(arm), ARM_WEETH_BALANCE - shares, "ARM weETH post");
        assertEq(weeth.balanceOf(address(adapter)), 0, "adapter weETH post");
        assertEq(eeth.balanceOf(address(adapter)), 0, "adapter eETH post");
        assertEq(eeth.balanceOf(address(etherfi)), shares, "queue eETH post");

        uint256 id = adapter.pendingRequestId(0);
        assertEq(adapter.requestShares(id), shares, "requestShares (weETH)");
        assertEq(adapter.requestAssets(id), shares, "requestAssets (eETH)");
    }

    function test_RequestRedeem_NonUnitRate() public {
        weeth.setRate(1.2e18); // 1 weETH = 1.2 eETH
        uint256 shares = 100 ether;

        vm.prank(arm);
        (uint256 sharesRequested, uint256 assetsExpected) = adapter.requestRedeem(shares);

        assertEq(sharesRequested, shares, "sharesRequested (weETH)");
        assertEq(assetsExpected, 120 ether, "assetsExpected (eETH after unwrap)");

        uint256 id = adapter.pendingRequestId(0);
        assertEq(adapter.requestShares(id), shares, "requestShares (weETH)");
        assertEq(adapter.requestAssets(id), 120 ether, "requestAssets (eETH)");
        // The vault request is denominated in unwrapped eETH.
        assertEq(eeth.balanceOf(address(etherfi)), 120 ether, "queue eETH post");
    }

    //////////////////////////////////////////////////////
    /// --- redeem
    //////////////////////////////////////////////////////
    function test_Redeem_SingleRequest() public {
        uint256 shares = 500 ether;

        vm.startPrank(arm);
        adapter.requestRedeem(shares);
        uint256 armWethBefore = weth.balanceOf(arm);
        uint256 id = adapter.pendingRequestId(0);

        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) = adapter.redeem(shares);
        vm.stopPrank();

        assertEq(sharesClaimed, shares, "sharesClaimed (weETH)");
        assertEq(assetsExpected, shares, "assetsExpected (eETH)");
        assertEq(assetsReceived, shares, "assetsReceived (WETH)");

        assertEq(weth.balanceOf(arm), armWethBefore + shares, "ARM weth post");
        assertEq(weth.balanceOf(address(adapter)), 0, "adapter weth post");
        assertEq(address(adapter).balance, 0, "adapter eth post");

        assertEq(adapter.requestShares(id), 0, "requestShares cleared");
        assertEq(adapter.requestAssets(id), 0, "requestAssets cleared");
    }

    function test_Redeem_NonUnitRate_AssetsScaleWithUnwrap() public {
        weeth.setRate(1.2e18); // 1 weETH = 1.2 eETH
        uint256 shares = 100 ether;

        vm.startPrank(arm);
        adapter.requestRedeem(shares);
        uint256 armWethBefore = weth.balanceOf(arm);

        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) = adapter.redeem(shares);
        vm.stopPrank();

        assertEq(sharesClaimed, shares, "sharesClaimed (weETH)");
        assertEq(assetsExpected, 120 ether, "assetsExpected (eETH)");
        assertEq(assetsReceived, 120 ether, "assetsReceived (WETH)");
        assertEq(weth.balanceOf(arm) - armWethBefore, 120 ether, "ARM weth delta");
    }

    function test_Redeem_MultipleRequests_FullDrain() public {
        vm.startPrank(arm);
        adapter.requestRedeem(400 ether);
        adapter.requestRedeem(600 ether);
        uint256 armWethBefore = weth.balanceOf(arm);

        (uint256 sharesClaimed,, uint256 assetsReceived) = adapter.redeem(1_000 ether);
        vm.stopPrank();

        assertEq(sharesClaimed, 1_000 ether, "sharesClaimed");
        assertEq(assetsReceived, 1_000 ether, "assetsReceived");
        assertEq(weth.balanceOf(arm), armWethBefore + 1_000 ether, "ARM weth post");
    }

    function test_Redeem_PartialDrain_FirstRequestOnly() public {
        vm.startPrank(arm);
        adapter.requestRedeem(400 ether);
        adapter.requestRedeem(600 ether);

        uint256 id0 = adapter.pendingRequestId(0);
        uint256 id1 = adapter.pendingRequestId(1);

        adapter.redeem(400 ether);
        vm.stopPrank();

        assertEq(adapter.requestShares(id0), 0, "id0 cleared");
        assertEq(adapter.requestShares(id1), 600 ether, "id1 retained");
        assertEq(adapter.requestAssets(id1), 600 ether, "id1 assets retained");
        assertEq(adapter.pendingRequestIdsLength(), 2, "pendingIds length unchanged");
    }

    function test_Redeem_RevertWhen_NoPendingRequests() public {
        vm.prank(arm);
        vm.expectRevert("Adapter: redeem exceeds claimable");
        adapter.redeem(1 ether);
    }

    function test_Redeem_RevertWhen_FirstRequestOvershoots() public {
        vm.startPrank(arm);
        adapter.requestRedeem(1_000 ether);
        adapter.requestRedeem(500 ether);
        vm.stopPrank();

        vm.prank(arm);
        vm.expectRevert("Adapter: invalid redeem amount");
        adapter.redeem(700 ether);
    }

    function test_Redeem_RevertWhen_FirstRequestNotFinalized() public {
        vm.prank(arm);
        adapter.requestRedeem(500 ether);
        uint256 id0 = adapter.pendingRequestId(0);
        etherfi.mock_setFinalized(id0, false);

        vm.prank(arm);
        vm.expectRevert("Mock EF: not finalized");
        adapter.redeem(500 ether);
    }

    //////////////////////////////////////////////////////
    /// --- getters / receivers
    //////////////////////////////////////////////////////
    function test_PendingRequestId_RevertWhen_OutOfBounds() public {
        vm.expectRevert();
        adapter.pendingRequestId(0);
    }

    function test_OnERC721Received_ReturnsSelector() public view {
        assertEq(
            adapter.onERC721Received(address(0), address(0), 0, ""),
            IERC721Receiver.onERC721Received.selector,
            "onERC721Received selector"
        );
    }

    function test_Receive_AcceptsEth() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(adapter).call{value: 1 ether}("");
        assertTrue(ok, "adapter accepts ETH");
        assertEq(address(adapter).balance, 1 ether, "adapter eth balance");
    }

    //////////////////////////////////////////////////////
    /// --- permissionless Ether.fi claim gate (Immunefi: NAV double-count)
    //////////////////////////////////////////////////////

    /// @notice ETH forwarded by the Ether.fi NFT contract outside an adapter-initiated claim is rejected
    ///         with `UnauthorizedEtherFiClaim`. This is the exact transfer EtherFi makes to the NFT owner
    ///         during a permissionless `claimWithdraw`; rejecting it (and thus reverting the claim) keeps the
    ///         withdrawal request — and the ARM's pending-redeem accounting — in sync.
    function test_Receive_RejectsNftForwardedEthOutsideClaim() public {
        vm.deal(address(etherfi), 1 ether);
        vm.prank(address(etherfi));
        (bool ok, bytes memory ret) = address(adapter).call{value: 1 ether}("");

        assertFalse(ok, "NFT-forwarded ETH must be rejected outside a claim");
        assertEq(bytes4(ret), WeETHAssetAdapter.UnauthorizedEtherFiClaim.selector, "revert selector");
        assertEq(address(adapter).balance, 0, "no ETH retained");
    }

    /// @notice A third party cannot claim an adapter-owned Ether.fi withdrawal NFT out-of-band. EtherFi
    ///         forwards proceeds to the NFT owner (the adapter) and reverts the whole claim (incl. the NFT burn)
    ///         if that transfer fails. The adapter rejects proceeds it did not initiate, so the permissionless
    ///         claim reverts and the request stays pending — the adapter's own claim still works afterward.
    ///         Without the gate this path would drop ETH into the adapter while the pending request survived,
    ///         double-counting it in the ARM's NAV (the reported vulnerability).
    function test_ExternalClaim_RevertWhen_NotAdapterInitiated() public {
        uint256 shares = 500 ether;

        vm.prank(arm);
        adapter.requestRedeem(shares);
        uint256 id = adapter.pendingRequestId(0);

        // Permissionless third-party claim: the mock (standing in for EtherFi's WithdrawRequestNFT)
        // forwards ETH to the owner, whose receive() rejects it; the mock bubbles that reason (EtherFi
        // would surface its own EthTransferFailed), so the whole claim reverts on the adapter's gate.
        vm.prank(alice);
        vm.expectRevert(WeETHAssetAdapter.UnauthorizedEtherFiClaim.selector);
        etherfi.claimWithdraw(id);

        // Request survives untouched: nothing claimed, share accounting intact, no stray ETH.
        (,,, bool claimed) = etherfi.requests(id);
        assertFalse(claimed, "request must stay unclaimed");
        assertEq(adapter.requestShares(id), shares, "requestShares intact");
        assertEq(address(adapter).balance, 0, "adapter holds no ETH");

        // The adapter's own claim path still works and delivers WETH to the ARM.
        uint256 armWethBefore = weth.balanceOf(arm);
        vm.prank(arm);
        (uint256 sharesClaimed,, uint256 assetsReceived) = adapter.redeem(shares);
        assertEq(sharesClaimed, shares, "adapter redeem claims the request");
        assertEq(weth.balanceOf(arm), armWethBefore + assetsReceived, "ARM received WETH");
    }
}
