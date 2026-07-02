// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";
import {Ownable} from "contracts/Ownable.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";

/// @notice Coverage for the Active Market admin surface on AbstractARM:
///         `addMarkets`, `removeMarket`, `setActiveMarket`, `setARMBuffer`.
contract Unit_MultiAssetARM_ManageMarket_Test is Unit_MultiAssetARM_Shared_Test {
    function setUp() public override {
        super.setUp();
        desactiveCapManager();
    }

    //////////////////////////////////////////////////////
    /// --- addMarkets
    //////////////////////////////////////////////////////
    function test_AddMarkets_Single() public {
        assertEq(arm.supportedMarkets(address(market)), false, "supported pre");

        address[] memory markets = new address[](1);
        markets[0] = address(market);

        vm.expectEmit(address(arm));
        emit AbstractARM.MarketAdded(address(market));

        vm.prank(governor);
        arm.addMarkets(markets);

        assertEq(arm.supportedMarkets(address(market)), true, "supported post");
    }

    function test_AddMarkets_Multiple() public {
        // Second slot is a fake address with a mocked asset() so we don't need a second real ERC4626.
        address fakeMarket = address(0x1234);
        vm.mockCall(fakeMarket, abi.encodeWithSignature("asset()"), abi.encode(address(liquidity)));

        address[] memory markets = new address[](2);
        markets[0] = address(market);
        markets[1] = fakeMarket;

        vm.expectEmit(address(arm));
        emit AbstractARM.MarketAdded(markets[0]);
        vm.expectEmit(address(arm));
        emit AbstractARM.MarketAdded(markets[1]);

        vm.prank(governor);
        arm.addMarkets(markets);

        assertEq(arm.supportedMarkets(markets[0]), true, "first supported");
        assertEq(arm.supportedMarkets(markets[1]), true, "second supported");
    }

    function test_AddMarkets_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        arm.addMarkets(new address[](0));
    }

    function test_AddMarkets_RevertWhen_AddressZero() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidMarket.selector);
        arm.addMarkets(new address[](1));
    }

    function test_AddMarkets_RevertWhen_AlreadySupported() public {
        addMarket(address(market));

        address[] memory markets = new address[](1);
        markets[0] = address(market);

        vm.prank(governor);
        vm.expectRevert(AbstractARM.MarketAlreadySupported.selector);
        arm.addMarkets(markets);
    }

    function test_AddMarkets_RevertWhen_InvalidMarketAsset() public {
        address fakeMarket = address(0x1234);
        vm.mockCall(fakeMarket, abi.encodeWithSignature("asset()"), abi.encode(address(0)));

        address[] memory markets = new address[](1);
        markets[0] = fakeMarket;

        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidMarketAsset.selector);
        arm.addMarkets(markets);
    }

    //////////////////////////////////////////////////////
    /// --- removeMarket
    //////////////////////////////////////////////////////
    function test_RemoveMarket_Default() public {
        addMarket(address(market));
        assertEq(arm.supportedMarkets(address(market)), true, "supported pre");

        vm.expectEmit(address(arm));
        emit AbstractARM.MarketRemoved(address(market));

        vm.prank(governor);
        arm.removeMarket(address(market));

        assertEq(arm.supportedMarkets(address(market)), false, "supported post");
    }

    function test_RemoveMarket_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.OnlyOwner.selector);
        arm.removeMarket(address(market));
    }

    function test_RemoveMarket_RevertWhen_AddressZero() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidMarket.selector);
        arm.removeMarket(address(0));
    }

    function test_RemoveMarket_RevertWhen_NotSupported() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.MarketNotSupported.selector);
        arm.removeMarket(address(market));
    }

    function test_RemoveMarket_RevertWhen_MarketIsActive() public {
        addMarket(address(market));
        setActiveMarket(address(market));

        vm.prank(governor);
        vm.expectRevert(AbstractARM.MarketActive.selector);
        arm.removeMarket(address(market));
    }

    //////////////////////////////////////////////////////
    /// --- setActiveMarket
    //////////////////////////////////////////////////////
    function test_SetActiveMarket_NoPreviousMarket() public {
        addMarket(address(market));
        assertEq(arm.activeMarket(), address(0), "activeMarket pre");

        vm.expectEmit(address(arm));
        emit AbstractARM.ActiveMarketUpdated(address(market));

        vm.prank(governor);
        arm.setActiveMarket(address(market));

        assertEq(arm.activeMarket(), address(market), "activeMarket post");
    }

    function test_SetActiveMarket_ToZero() public {
        addMarket(address(market));
        setActiveMarket(address(market));
        assertEq(arm.activeMarket(), address(market), "activeMarket pre");

        vm.expectEmit(address(arm));
        emit AbstractARM.ActiveMarketUpdated(address(0));

        vm.prank(governor);
        arm.setActiveMarket(address(0));

        assertEq(arm.activeMarket(), address(0), "activeMarket post");
    }

    function test_SetActiveMarket_WithPreviousMarket_Empty() public {
        addMarket(address(market));
        setActiveMarket(address(market));
        addMarket(address(market2));
        assertEq(market.balanceOf(address(arm)), 0, "prev market shares pre");

        vm.expectEmit(address(arm));
        emit AbstractARM.ActiveMarketUpdated(address(market2));

        vm.prank(governor);
        arm.setActiveMarket(address(market2));

        assertEq(arm.activeMarket(), address(market2), "activeMarket post");
        assertEq(market.balanceOf(address(arm)), 0, "prev market shares post");
    }

    function test_SetActiveMarket_WithPreviousMarket_NonEmpty_WithShares() public {
        // Deposit alice → ARM holds liquid WETH. Buffer 0 + active market triggers an allocation,
        // so by the time we switch markets, the previous market actually holds the ARM's shares.
        aliceFirstDeposit();
        addMarket(address(market));
        setActiveMarket(address(market));
        addMarket(address(market2));

        uint256 prevMarketShares = market.balanceOf(address(arm));
        assertGt(prevMarketShares, 0, "prev market shares pre");

        vm.expectEmit(address(arm));
        emit AbstractARM.ActiveMarketUpdated(address(market2));

        vm.prank(governor);
        arm.setActiveMarket(address(market2));

        // All shares were redeemed from the previous market before switching.
        assertEq(arm.activeMarket(), address(market2), "activeMarket post");
        assertEq(market.balanceOf(address(arm)), 0, "prev market shares post");
    }

    function test_SetActiveMarket_ToSameMarket() public {
        addMarket(address(market));
        setActiveMarket(address(market));

        // Early-return path — should not emit ActiveMarketUpdated again. Recording logs lets us
        // assert no event was emitted by the second call.
        vm.recordLogs();
        vm.prank(governor);
        arm.setActiveMarket(address(market));
        assertEq(vm.getRecordedLogs().length, 0, "no events emitted");

        assertEq(arm.activeMarket(), address(market), "activeMarket unchanged");
    }

    function test_SetActiveMarket_RevertWhen_NotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        arm.setActiveMarket(address(market));
    }

    function test_SetActiveMarket_RevertWhen_NotSupported() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.MarketNotSupported.selector);
        arm.setActiveMarket(address(market));
    }

    //////////////////////////////////////////////////////
    /// --- setARMBuffer
    //////////////////////////////////////////////////////
    function test_SetARMBuffer_Default() public {
        uint256 newBuffer = 0.3 ether;
        assertEq(arm.armBuffer(), 0, "armBuffer pre");

        vm.expectEmit(address(arm));
        emit AbstractARM.ARMBufferUpdated(newBuffer);

        vm.prank(governor);
        arm.setARMBuffer(newBuffer);

        assertEq(arm.armBuffer(), newBuffer, "armBuffer post");
    }

    function test_SetARMBuffer_RevertWhen_NotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(OwnableOperable.OnlyOperatorOrOwner.selector);
        arm.setARMBuffer(0);
    }

    function test_SetARMBuffer_RevertWhen_Above1e18() public {
        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidARMBuffer.selector);
        arm.setARMBuffer(1e18 + 1);
    }
}
