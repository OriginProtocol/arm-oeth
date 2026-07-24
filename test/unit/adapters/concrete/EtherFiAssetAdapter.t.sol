// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Test} from "forge-std/Test.sol";

// Contracts
import {EtherFiAssetAdapter} from "contracts/adapters/EtherFiAssetAdapter.sol";

// External
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {WETH} from "@solmate/tokens/WETH.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

// Mocks
import {MockEtherFiWithdraw} from "../mocks/MockEtherFiWithdraw.sol";

/// @notice Unit tests for `EtherFiAssetAdapter` (eETH, 1:1 share/asset math) driven directly by
///         pranking the ARM address. The Ether.fi withdrawal queue and withdrawal NFT are both backed
///         by a single `MockEtherFiWithdraw` double.
contract Unit_EtherFiAssetAdapter_Test is Test {
    EtherFiAssetAdapter internal adapter;
    MockEtherFiWithdraw internal etherfi;
    WETH internal weth;
    MockERC20 internal eeth;

    address internal arm = makeAddr("arm");
    address internal alice = makeAddr("alice");

    uint256 internal constant ARM_EETH_BALANCE = 5_000 ether;

    function setUp() public {
        weth = new WETH();
        eeth = new MockERC20("Ether.fi ETH", "eETH", 18);
        etherfi = new MockEtherFiWithdraw(address(eeth));

        adapter = new EtherFiAssetAdapter(arm, address(eeth), address(weth), address(etherfi), address(etherfi));
        adapter.initialize();

        // Fund the queue with ETH so claims can pay out, and seed the ARM with eETH.
        vm.deal(address(etherfi), 100_000 ether);
        eeth.mint(arm, ARM_EETH_BALANCE);
        vm.prank(arm);
        eeth.approve(address(adapter), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- initialize / view / approvals
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

    function test_ConvertToAssets_OneToOne() public view {
        assertEq(adapter.convertToAssets(123 ether), 123 ether, "convertToAssets 1:1");
    }

    function test_ConvertToShares_OneToOne() public view {
        assertEq(adapter.convertToShares(123 ether), 123 ether, "convertToShares 1:1");
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
    function test_RequestRedeem_Single() public {
        uint256 shares = 500 ether;

        vm.prank(arm);
        (uint256 sharesRequested, uint256 assetsExpected) = adapter.requestRedeem(shares);

        assertEq(sharesRequested, shares, "sharesRequested");
        assertEq(assetsExpected, shares, "assetsExpected 1:1");

        // eETH flowed ARM -> adapter -> queue; adapter holds no residual eETH.
        assertEq(eeth.balanceOf(arm), ARM_EETH_BALANCE - shares, "ARM eETH post");
        assertEq(eeth.balanceOf(address(adapter)), 0, "adapter eETH post");
        assertEq(eeth.balanceOf(address(etherfi)), shares, "queue eETH post");

        // Adapter storage tracks the request.
        assertEq(adapter.pendingRequestIdsLength(), 1, "pendingIds post");
        uint256 id = adapter.pendingRequestId(0);
        assertEq(adapter.requestShares(id), shares, "requestShares");

        // Queue recorded the adapter as the recipient.
        (address recipient, uint256 amount,, bool claimed) = etherfi.requests(id);
        assertEq(recipient, address(adapter), "request.recipient");
        assertEq(amount, shares, "request.amount");
        assertEq(claimed, false, "request.claimed");
    }

    function test_RequestRedeem_TwoSequentialCalls() public {
        vm.startPrank(arm);
        adapter.requestRedeem(300 ether);
        adapter.requestRedeem(200 ether);
        vm.stopPrank();

        assertEq(adapter.pendingRequestIdsLength(), 2, "pendingIds after two calls");
        uint256 id0 = adapter.pendingRequestId(0);
        uint256 id1 = adapter.pendingRequestId(1);
        assertTrue(id0 != id1, "ids distinct");
        assertEq(adapter.requestShares(id0), 300 ether, "first request shares");
        assertEq(adapter.requestShares(id1), 200 ether, "second request shares");
    }

    //////////////////////////////////////////////////////
    /// --- redeem — happy paths
    //////////////////////////////////////////////////////
    function test_Redeem_SingleRequest() public {
        uint256 shares = 500 ether;

        vm.startPrank(arm);
        adapter.requestRedeem(shares);
        uint256 armWethBefore = weth.balanceOf(arm);
        uint256 id = adapter.pendingRequestId(0);

        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) = adapter.redeem(shares);
        vm.stopPrank();

        assertEq(sharesClaimed, shares, "sharesClaimed");
        assertEq(assetsExpected, shares, "assetsExpected");
        assertEq(assetsReceived, shares, "assetsReceived");

        // WETH lands on the ARM; adapter holds no residual ETH or WETH.
        assertEq(weth.balanceOf(arm), armWethBefore + shares, "ARM weth post");
        assertEq(weth.balanceOf(address(adapter)), 0, "adapter weth post");
        assertEq(address(adapter).balance, 0, "adapter eth post");

        // Mapping cleared and queue marked claimed.
        assertEq(adapter.requestShares(id), 0, "requestShares cleared");
        (,,, bool claimed) = etherfi.requests(id);
        assertTrue(claimed, "queue.claimed");
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
        uint256 armWethBefore = weth.balanceOf(arm);

        (uint256 sharesClaimed,, uint256 assetsReceived) = adapter.redeem(400 ether);
        vm.stopPrank();

        assertEq(sharesClaimed, 400 ether, "sharesClaimed");
        assertEq(assetsReceived, 400 ether, "assetsReceived");
        assertEq(weth.balanceOf(arm), armWethBefore + 400 ether, "ARM weth post");

        // Only id0 cleared; id1 still queued. Array length unchanged, cursor advanced.
        assertEq(adapter.requestShares(id0), 0, "id0 cleared");
        assertEq(adapter.requestShares(id1), 600 ether, "id1 retained");
        assertEq(adapter.pendingRequestIdsLength(), 2, "pendingIds length unchanged");
    }

    function test_Redeem_WrapsEthToWeth() public {
        uint256 shares = 750 ether;

        vm.startPrank(arm);
        adapter.requestRedeem(shares);
        uint256 armWethBefore = weth.balanceOf(arm);
        adapter.redeem(shares);
        vm.stopPrank();

        assertEq(address(adapter).balance, 0, "adapter eth post");
        assertEq(weth.balanceOf(address(adapter)), 0, "adapter weth post");
        assertEq(weth.balanceOf(arm) - armWethBefore, shares, "ARM weth delta == eth received");
    }

    //////////////////////////////////////////////////////
    /// --- redeem — revert branches
    //////////////////////////////////////////////////////
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

        // 700 overshoots the first request (1000) and is not a clean prefix sum.
        vm.prank(arm);
        vm.expectRevert("Adapter: invalid redeem amount");
        adapter.redeem(700 ether);
    }

    function test_Redeem_RevertWhen_BetweenRequests() public {
        vm.startPrank(arm);
        adapter.requestRedeem(1_000 ether);
        adapter.requestRedeem(500 ether);
        vm.stopPrank();

        // 1200 lands between the two request prefix sums (1000 and 1500).
        vm.prank(arm);
        vm.expectRevert("Adapter: invalid redeem amount");
        adapter.redeem(1_200 ether);
    }

    function test_Redeem_RevertWhen_FirstRequestNotFinalized() public {
        vm.prank(arm);
        adapter.requestRedeem(500 ether);
        uint256 id0 = adapter.pendingRequestId(0);
        etherfi.mock_setFinalized(id0, false);

        // FIFO accounting passes, but the queue rejects the un-finalized claim.
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
        assertEq(bytes4(ret), EtherFiAssetAdapter.UnauthorizedEtherFiClaim.selector, "revert selector");
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
        // forwards ETH to the owner and require()s the transfer, which the adapter's gate rejects.
        vm.prank(alice);
        vm.expectRevert("Mock EF: eth transfer failed");
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
