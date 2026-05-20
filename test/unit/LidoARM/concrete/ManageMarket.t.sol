// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_LidoARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";
import {Ownable} from "contracts/Ownable.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";

/// @notice Coverage for the Active Market admin surface on AbstractARM:
///         `addMarkets`, `removeMarket`, `setActiveMarket`, `setARMBuffer`.
contract Unit_LidoARM_ManageMarket_Test is Unit_LidoARM_Shared_Test {
    function setUp() public override {
        super.setUp();
        desactiveCapManager();
    }

    //////////////////////////////////////////////////////
    /// --- addMarkets
    //////////////////////////////////////////////////////
    function test_AddMarkets_Single() public {
        assertEq(lidoARM.supportedMarkets(address(mockERC4626Market)), false, "supported pre");

        address[] memory markets = new address[](1);
        markets[0] = address(mockERC4626Market);

        vm.expectEmit(address(lidoARM));
        emit AbstractARM.MarketAdded(address(mockERC4626Market));

        vm.prank(governor);
        lidoARM.addMarkets(markets);

        assertEq(lidoARM.supportedMarkets(address(mockERC4626Market)), true, "supported post");
    }

    function test_AddMarkets_Multiple() public {
        // Second slot is a fake address with a mocked asset() so we don't need a second real ERC4626.
        address fakeMarket = address(0x1234);
        vm.mockCall(fakeMarket, abi.encodeWithSignature("asset()"), abi.encode(address(weth)));

        address[] memory markets = new address[](2);
        markets[0] = address(mockERC4626Market);
        markets[1] = fakeMarket;

        vm.expectEmit(address(lidoARM));
        emit AbstractARM.MarketAdded(markets[0]);
        vm.expectEmit(address(lidoARM));
        emit AbstractARM.MarketAdded(markets[1]);

        vm.prank(governor);
        lidoARM.addMarkets(markets);

        assertEq(lidoARM.supportedMarkets(markets[0]), true, "first supported");
        assertEq(lidoARM.supportedMarkets(markets[1]), true, "second supported");
    }

    function test_AddMarkets_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        lidoARM.addMarkets(new address[](0));
    }

    function test_AddMarkets_RevertWhen_AddressZero() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidMarket.selector);
        lidoARM.addMarkets(new address[](1));
    }

    function test_AddMarkets_RevertWhen_AlreadySupported() public {
        addMarket(address(mockERC4626Market));

        address[] memory markets = new address[](1);
        markets[0] = address(mockERC4626Market);

        vm.prank(governor);
        vm.expectRevert(AbstractARM.MarketAlreadySupported.selector);
        lidoARM.addMarkets(markets);
    }

    function test_AddMarkets_RevertWhen_InvalidMarketAsset() public {
        address fakeMarket = address(0x1234);
        vm.mockCall(fakeMarket, abi.encodeWithSignature("asset()"), abi.encode(address(0)));

        address[] memory markets = new address[](1);
        markets[0] = fakeMarket;

        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidMarketAsset.selector);
        lidoARM.addMarkets(markets);
    }

    //////////////////////////////////////////////////////
    /// --- removeMarket
    //////////////////////////////////////////////////////
    function test_RemoveMarket_Default() public {
        addMarket(address(mockERC4626Market));
        assertEq(lidoARM.supportedMarkets(address(mockERC4626Market)), true, "supported pre");

        vm.expectEmit(address(lidoARM));
        emit AbstractARM.MarketRemoved(address(mockERC4626Market));

        vm.prank(governor);
        lidoARM.removeMarket(address(mockERC4626Market));

        assertEq(lidoARM.supportedMarkets(address(mockERC4626Market)), false, "supported post");
    }

    function test_RemoveMarket_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        lidoARM.removeMarket(address(mockERC4626Market));
    }

    function test_RemoveMarket_RevertWhen_AddressZero() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidMarket.selector);
        lidoARM.removeMarket(address(0));
    }

    function test_RemoveMarket_RevertWhen_NotSupported() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.MarketNotSupported.selector);
        lidoARM.removeMarket(address(mockERC4626Market));
    }

    function test_RemoveMarket_RevertWhen_MarketIsActive() public {
        addMarket(address(mockERC4626Market));
        setActiveMarket(address(mockERC4626Market));

        vm.prank(governor);
        vm.expectRevert(AbstractARM.MarketActive.selector);
        lidoARM.removeMarket(address(mockERC4626Market));
    }

    //////////////////////////////////////////////////////
    /// --- setActiveMarket
    //////////////////////////////////////////////////////
    function test_SetActiveMarket_NoPreviousMarket() public {
        addMarket(address(mockERC4626Market));
        assertEq(lidoARM.activeMarket(), address(0), "activeMarket pre");

        vm.expectEmit(address(lidoARM));
        emit AbstractARM.ActiveMarketUpdated(address(mockERC4626Market));

        vm.prank(governor);
        lidoARM.setActiveMarket(address(mockERC4626Market));

        assertEq(lidoARM.activeMarket(), address(mockERC4626Market), "activeMarket post");
    }

    function test_SetActiveMarket_ToZero() public {
        addMarket(address(mockERC4626Market));
        setActiveMarket(address(mockERC4626Market));
        assertEq(lidoARM.activeMarket(), address(mockERC4626Market), "activeMarket pre");

        vm.expectEmit(address(lidoARM));
        emit AbstractARM.ActiveMarketUpdated(address(0));

        vm.prank(governor);
        lidoARM.setActiveMarket(address(0));

        assertEq(lidoARM.activeMarket(), address(0), "activeMarket post");
    }

    function test_SetActiveMarket_WithPreviousMarket_Empty() public {
        addMarket(address(mockERC4626Market));
        setActiveMarket(address(mockERC4626Market));
        addMarket(address(mockERC4626Market2));
        assertEq(mockERC4626Market.balanceOf(address(lidoARM)), 0, "prev market shares pre");

        vm.expectEmit(address(lidoARM));
        emit AbstractARM.ActiveMarketUpdated(address(mockERC4626Market2));

        vm.prank(governor);
        lidoARM.setActiveMarket(address(mockERC4626Market2));

        assertEq(lidoARM.activeMarket(), address(mockERC4626Market2), "activeMarket post");
        assertEq(mockERC4626Market.balanceOf(address(lidoARM)), 0, "prev market shares post");
    }

    function test_SetActiveMarket_WithPreviousMarket_NonEmpty_WithShares() public {
        // Deposit alice → ARM holds liquid WETH. Buffer 0 + active market triggers an allocation,
        // so by the time we switch markets, the previous market actually holds the ARM's shares.
        aliceFirstDeposit();
        addMarket(address(mockERC4626Market));
        setActiveMarket(address(mockERC4626Market));
        addMarket(address(mockERC4626Market2));

        uint256 prevMarketShares = mockERC4626Market.balanceOf(address(lidoARM));
        assertGt(prevMarketShares, 0, "prev market shares pre");

        vm.expectEmit(address(lidoARM));
        emit AbstractARM.ActiveMarketUpdated(address(mockERC4626Market2));

        vm.prank(governor);
        lidoARM.setActiveMarket(address(mockERC4626Market2));

        // All shares were redeemed from the previous market before switching.
        assertEq(lidoARM.activeMarket(), address(mockERC4626Market2), "activeMarket post");
        assertEq(mockERC4626Market.balanceOf(address(lidoARM)), 0, "prev market shares post");
    }

    function test_SetActiveMarket_ToSameMarket() public {
        addMarket(address(mockERC4626Market));
        setActiveMarket(address(mockERC4626Market));

        // Early-return path — should not emit ActiveMarketUpdated again. Recording logs lets us
        // assert no event was emitted by the second call.
        vm.recordLogs();
        vm.prank(governor);
        lidoARM.setActiveMarket(address(mockERC4626Market));
        assertEq(vm.getRecordedLogs().length, 0, "no events emitted");

        assertEq(lidoARM.activeMarket(), address(mockERC4626Market), "activeMarket unchanged");
    }

    function test_SetActiveMarket_RevertWhen_NotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        lidoARM.setActiveMarket(address(mockERC4626Market));
    }

    function test_SetActiveMarket_RevertWhen_NotSupported() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.MarketNotSupported.selector);
        lidoARM.setActiveMarket(address(mockERC4626Market));
    }

    //////////////////////////////////////////////////////
    /// --- setARMBuffer
    //////////////////////////////////////////////////////
    function test_SetARMBuffer_Default() public {
        uint256 newBuffer = 0.3 ether;
        assertEq(lidoARM.armBuffer(), 0, "armBuffer pre");

        vm.expectEmit(address(lidoARM));
        emit AbstractARM.ARMBufferUpdated(newBuffer);

        vm.prank(governor);
        lidoARM.setARMBuffer(newBuffer);

        assertEq(lidoARM.armBuffer(), newBuffer, "armBuffer post");
    }

    function test_SetARMBuffer_RevertWhen_NotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        lidoARM.setARMBuffer(0);
    }

    function test_SetARMBuffer_RevertWhen_Above1e18() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidARMBuffer.selector);
        lidoARM.setARMBuffer(1e18 + 1);
    }
}
