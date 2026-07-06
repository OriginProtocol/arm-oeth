// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Test} from "forge-std/Test.sol";

// Contracts
import {EthenaAssetAdapter} from "contracts/adapters/EthenaAssetAdapter.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Ownable} from "contracts/Ownable.sol";

// External
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

// Mocks
import {MockStakedUSDe} from "../mocks/MockStakedUSDe.sol";

/// @notice Unit tests for `EthenaAssetAdapter`. The adapter rotates sUSDe cooldowns across a fixed set of
///         `EthenaUnstaker` helpers, so it is deployed behind a `Proxy` (the proxy owner seeds the helpers
///         via `deployUnstakers`). The ARM is a plain pranked address holding sUSDe.
contract Unit_EthenaAssetAdapter_Test is Test {
    EthenaAssetAdapter internal adapter;
    MockStakedUSDe internal susde;
    MockERC20 internal usde;

    address internal arm = makeAddr("arm");
    address internal governor = makeAddr("governor");
    address internal alice = makeAddr("alice");

    uint256 internal constant ARM_SUSDE_BALANCE = 5_000 ether;
    uint256 internal constant DELAY_REQUEST = 30 minutes;
    uint256 internal constant COOLDOWN = 7 days;

    function setUp() public {
        usde = new MockERC20("USDe", "USDe", 18);
        susde = new MockStakedUSDe(address(usde));
        // Fund sUSDe with USDe so cooldown claims can pay out.
        usde.mint(address(susde), 1e30);

        adapter = EthenaAssetAdapter(_deployAdapterWithUnstakers());

        // Seed the ARM with sUSDe and approve the adapter (proxy) to pull it.
        susde.mint(arm, ARM_SUSDE_BALANCE);
        vm.prank(arm);
        ERC20(address(susde)).approve(address(adapter), type(uint256).max);

        // Move past the first request-delay window (lastRequestTimestamp starts at 0).
        vm.warp(1_000_000);
    }

    /// @dev Deploys the adapter behind a proxy owned by `governor` and seeds the unstaker helpers.
    function _deployAdapterWithUnstakers() internal returns (address) {
        EthenaAssetAdapter impl = new EthenaAssetAdapter(arm, address(usde), address(susde));
        Proxy proxy = new Proxy();
        proxy.initialize(address(impl), governor, "");
        vm.prank(governor);
        EthenaAssetAdapter(address(proxy)).deployUnstakers();
        return address(proxy);
    }

    //////////////////////////////////////////////////////
    /// --- view / conversions
    //////////////////////////////////////////////////////
    function test_Asset_ReturnsUsde() public view {
        assertEq(adapter.asset(), address(usde), "asset");
    }

    function test_ConvertToAssets_DelegatesToSusde() public {
        susde.setRate(1.1e18); // 1 sUSDe = 1.1 USDe
        assertEq(adapter.convertToAssets(100 ether), susde.convertToAssets(100 ether), "delegates");
        assertEq(adapter.convertToAssets(100 ether), 110 ether, "value");
    }

    function test_ConvertToShares_DelegatesToSusde() public {
        susde.setRate(1.25e18); // 1 sUSDe = 1.25 USDe
        assertEq(adapter.convertToShares(125 ether), susde.convertToShares(125 ether), "delegates");
        assertEq(adapter.convertToShares(125 ether), 100 ether, "value");
    }

    function test_UnstakerIndexAt_WrapsModuloMaxUnstakers() public view {
        assertEq(adapter.unstakerIndexAt(0), 0, "idx 0");
        assertEq(adapter.unstakerIndexAt(41), 41, "idx 41");
        assertEq(adapter.unstakerIndexAt(42), 0, "idx wraps at MAX_UNSTAKERS");
    }

    function test_DeployUnstakers_PopulatedHelpers() public view {
        assertTrue(adapter.unstakers(0) != address(0), "unstaker 0 set");
        assertTrue(adapter.unstakers(41) != address(0), "unstaker 41 set");
    }

    //////////////////////////////////////////////////////
    /// --- modifiers / access control
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

    function test_DeployUnstakers_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        adapter.deployUnstakers();
    }

    function test_SetUnstakers_RevertWhen_NotOwner() public {
        address[42] memory fresh;
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        adapter.setUnstakers(fresh);
    }

    //////////////////////////////////////////////////////
    /// --- requestRedeem
    //////////////////////////////////////////////////////
    function test_RequestRedeem_RevertWhen_InvalidUnstaker() public {
        // Fresh adapter behind a proxy but without seeded unstakers.
        EthenaAssetAdapter impl = new EthenaAssetAdapter(arm, address(usde), address(susde));
        Proxy proxy = new Proxy();
        proxy.initialize(address(impl), governor, "");
        EthenaAssetAdapter bare = EthenaAssetAdapter(address(proxy));

        susde.mint(arm, 100 ether);
        vm.prank(arm);
        ERC20(address(susde)).approve(address(bare), type(uint256).max);

        vm.prank(arm);
        vm.expectRevert("Adapter: invalid unstaker");
        bare.requestRedeem(100 ether);
    }

    function test_RequestRedeem_Single() public {
        uint256 shares = 500 ether;
        address unstaker0 = adapter.unstakers(0);

        vm.prank(arm);
        (uint256 sharesRequested, uint256 assetsExpected) = adapter.requestRedeem(shares);

        assertEq(sharesRequested, shares, "sharesRequested");
        assertEq(assetsExpected, shares, "assetsExpected (1:1)");

        // sUSDe left the ARM; the unstaker burned it into a cooldown.
        assertEq(ERC20(address(susde)).balanceOf(arm), ARM_SUSDE_BALANCE - shares, "ARM sUSDe post");
        assertEq(ERC20(address(susde)).balanceOf(unstaker0), 0, "unstaker sUSDe burned");

        // Adapter bookkeeping.
        assertEq(adapter.requestShares(unstaker0), shares, "requestShares");
        assertEq(adapter.requestAssets(unstaker0), shares, "requestAssets");
        assertEq(adapter.totalRequests(), 1, "totalRequests");
        assertEq(adapter.nextUnstakerIndex(), 1, "nextUnstakerIndex advanced");
        assertEq(adapter.lastRequestTimestamp(), uint32(block.timestamp), "lastRequestTimestamp");

        // Cooldown recorded against the unstaker.
        (, uint152 underlyingAmount) = susde.cooldowns(unstaker0);
        assertEq(underlyingAmount, shares, "unstaker cooldown amount");
    }

    function test_RequestRedeem_RevertWhen_DelayNotPassed() public {
        vm.prank(arm);
        adapter.requestRedeem(100 ether);

        // A second request within the delay window reverts.
        vm.prank(arm);
        vm.expectRevert("Adapter: delay not passed");
        adapter.requestRedeem(100 ether);
    }

    function test_RequestRedeem_RotatesUnstakers() public {
        address unstaker0 = adapter.unstakers(0);
        address unstaker1 = adapter.unstakers(1);

        vm.prank(arm);
        adapter.requestRedeem(300 ether);

        // Respect the per-request delay before the next request.
        vm.warp(block.timestamp + DELAY_REQUEST);
        vm.prank(arm);
        adapter.requestRedeem(200 ether);

        assertEq(adapter.requestShares(unstaker0), 300 ether, "unstaker0 shares");
        assertEq(adapter.requestShares(unstaker1), 200 ether, "unstaker1 shares");
        assertEq(adapter.totalRequests(), 2, "totalRequests");
        assertEq(adapter.nextUnstakerIndex(), 2, "nextUnstakerIndex");
    }

    //////////////////////////////////////////////////////
    /// --- redeem
    //////////////////////////////////////////////////////
    function test_Redeem_SingleRequest() public {
        uint256 shares = 500 ether;
        address unstaker0 = adapter.unstakers(0);

        vm.prank(arm);
        adapter.requestRedeem(shares);

        // Wait out the sUSDe cooldown.
        vm.warp(block.timestamp + COOLDOWN + 1);

        uint256 armUsdeBefore = usde.balanceOf(arm);
        vm.prank(arm);
        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) = adapter.redeem(shares);

        assertEq(sharesClaimed, shares, "sharesClaimed");
        assertEq(assetsExpected, shares, "assetsExpected");
        assertEq(assetsReceived, shares, "assetsReceived");

        // USDe lands on the ARM; adapter holds none.
        assertEq(usde.balanceOf(arm), armUsdeBefore + shares, "ARM USDe post");
        assertEq(usde.balanceOf(address(adapter)), 0, "adapter USDe post");

        // Bookkeeping cleared and cooldown consumed.
        assertEq(adapter.requestShares(unstaker0), 0, "requestShares cleared");
        (, uint152 underlyingAmount) = susde.cooldowns(unstaker0);
        assertEq(underlyingAmount, 0, "cooldown cleared");
    }

    function test_Redeem_MultipleRequests_FullDrain() public {
        vm.prank(arm);
        adapter.requestRedeem(300 ether);
        vm.warp(block.timestamp + DELAY_REQUEST);
        vm.prank(arm);
        adapter.requestRedeem(200 ether);

        vm.warp(block.timestamp + COOLDOWN + 1);

        uint256 armUsdeBefore = usde.balanceOf(arm);
        vm.prank(arm);
        (uint256 sharesClaimed,, uint256 assetsReceived) = adapter.redeem(500 ether);

        assertEq(sharesClaimed, 500 ether, "sharesClaimed");
        assertEq(assetsReceived, 500 ether, "assetsReceived");
        assertEq(usde.balanceOf(arm), armUsdeBefore + 500 ether, "ARM USDe post");
    }

    function test_Redeem_PartialDrain_FirstRequestOnly() public {
        address unstaker0 = adapter.unstakers(0);
        address unstaker1 = adapter.unstakers(1);

        vm.prank(arm);
        adapter.requestRedeem(300 ether);
        vm.warp(block.timestamp + DELAY_REQUEST);
        vm.prank(arm);
        adapter.requestRedeem(200 ether);

        vm.warp(block.timestamp + COOLDOWN + 1);

        vm.prank(arm);
        adapter.redeem(300 ether);

        assertEq(adapter.requestShares(unstaker0), 0, "unstaker0 cleared");
        assertEq(adapter.requestShares(unstaker1), 200 ether, "unstaker1 retained");
    }

    function test_Redeem_RevertWhen_ExceedsClaimable() public {
        vm.prank(arm);
        vm.expectRevert("Adapter: redeem exceeds claimable");
        adapter.redeem(1 ether);
    }

    function test_Redeem_RevertWhen_FirstRequestOvershoots() public {
        vm.prank(arm);
        adapter.requestRedeem(300 ether);
        vm.warp(block.timestamp + DELAY_REQUEST);
        vm.prank(arm);
        adapter.requestRedeem(200 ether);

        vm.warp(block.timestamp + COOLDOWN + 1);

        // 250 overshoots the first request (300) and is not a clean prefix sum.
        vm.prank(arm);
        vm.expectRevert("Adapter: invalid redeem amount");
        adapter.redeem(250 ether);
    }

    function test_Redeem_RevertWhen_BetweenRequests() public {
        vm.prank(arm);
        adapter.requestRedeem(300 ether);
        vm.warp(block.timestamp + DELAY_REQUEST);
        vm.prank(arm);
        adapter.requestRedeem(200 ether);

        vm.warp(block.timestamp + COOLDOWN + 1);

        // 400 lands between the request prefix sums (300 and 500).
        vm.prank(arm);
        vm.expectRevert("Adapter: invalid redeem amount");
        adapter.redeem(400 ether);
    }
}
