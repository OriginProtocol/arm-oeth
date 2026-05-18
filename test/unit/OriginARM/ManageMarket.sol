// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

contract Unit_Concrete_OriginARM_ManageMarket_Test_ is Unit_Shared_Test {
    ////////////////////////////////////////////////////
    /// --- SETUP
    ////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();

        // Give Alice some WETH
        deal(address(weth), alice, 1_000 * DEFAULT_AMOUNT);

        // Alice approve max WETH to the ARM
        vm.prank(alice);
        weth.approve(address(originARM), type(uint256).max);
    }

    ////////////////////////////////////////////////////
    /// --- REVERTS
    ////////////////////////////////////////////////////
    function test_RevertWhen_AddMarkets_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert(bytes4(keccak256("OnlyOwner()")));
        originARM.addMarkets(new address[](0));
    }

    function test_RevertWhen_AddMarkets_Because_AddressZero() public asGovernor {
        vm.expectRevert(bytes4(keccak256("InvalidMarket()")));
        originARM.addMarkets(new address[](1));
    }

    function test_RevertWhen_AddMarkets_Because_MarketAlreadySupported()
        public
        setARMBuffer(0)
        addMarket(address(market))
        setActiveMarket(address(market))
        asGovernor
    {
        address[] memory strategies = new address[](1);
        strategies[0] = address(market);
        vm.expectRevert(bytes4(keccak256("MarketAlreadySupported()")));
        originARM.addMarkets(strategies);
    }

    function test_RevertWhen_AddMarkets_Because_InvalidMarketAsset() public asGovernor {
        address[] memory strategies = new address[](1);
        strategies[0] = address(0x123);
        // Using mockCall to simulate the asset() function on a simple address
        vm.mockCall(strategies[0], abi.encodeWithSignature("asset()"), abi.encode(address(0)));
        vm.expectRevert(bytes4(keccak256("InvalidMarketAsset()")));
        originARM.addMarkets(strategies);
    }

    function test_RevertWhen_RemoveMarket_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert(bytes4(keccak256("OnlyOwner()")));
        originARM.removeMarket(address(market));
    }

    function test_RevertWhen_RemoveMarket_Because_MarketIsAddressZero() public asGovernor {
        vm.expectRevert(bytes4(keccak256("InvalidMarket()")));
        originARM.removeMarket(address(0));
    }

    function test_RevertWhen_RemoveMarket_Because_MarketNotSupported() public asGovernor {
        vm.expectRevert(bytes4(keccak256("MarketNotSupported()")));
        originARM.removeMarket(address(market));
    }

    function test_RevertWhen_RemoveMarket_Because_MarketIsActive()
        public
        forceAvailableAssetsToZero
        addMarket(address(market))
        setActiveMarket(address(market))
        asGovernor
    {
        vm.expectRevert(bytes4(keccak256("MarketActive()")));
        originARM.removeMarket(address(market));
    }

    function test_RevertWhen_SetActiveMarket_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert(bytes4(keccak256("OnlyOperatorOrOwner()")));
        originARM.setActiveMarket(address(market));
    }

    function test_RevertWhen_SetActiveMarket_Because_MarketNotSupported() public asGovernor {
        vm.expectRevert(bytes4(keccak256("MarketNotSupported()")));
        originARM.setActiveMarket(address(market));
    }

    ////////////////////////////////////////////////////
    /// --- TESTS
    ////////////////////////////////////////////////////

    function test_AddMarkets_Single() public asGovernor {
        // Assertions before
        assertEq(originARM.supportedMarkets(address(market)), false);

        address[] memory strategies = new address[](1);
        strategies[0] = address(market);
        vm.expectEmit(address(originARM));
        emit AbstractARM.MarketAdded(address(market));
        originARM.addMarkets(strategies);

        // Assertions after
        assertEq(originARM.supportedMarkets(address(market)), true);
    }

    function test_AddMarkets_Multiple() public asGovernor {
        address[] memory strategies = new address[](2);
        strategies[0] = address(market);
        strategies[1] = address(0x1234);
        // Using mockCall to simulate the asset() function on a simple address
        vm.mockCall(strategies[1], abi.encodeWithSignature("asset()"), abi.encode(address(weth)));

        // Assertions before
        assertEq(originARM.supportedMarkets(strategies[0]), false);
        assertEq(originARM.supportedMarkets(strategies[1]), false);

        vm.expectEmit(address(originARM));
        emit AbstractARM.MarketAdded(strategies[0]);
        emit AbstractARM.MarketAdded(strategies[1]);
        originARM.addMarkets(strategies);

        // Assertions after
        assertEq(originARM.supportedMarkets(strategies[0]), true);
        assertEq(originARM.supportedMarkets(strategies[1]), true);
    }

    function test_RemoveMarket() public addMarket(address(market)) asGovernor {
        // Assertions before
        assertEq(originARM.supportedMarkets(address(market)), true);

        vm.expectEmit(address(originARM));
        emit AbstractARM.MarketRemoved(address(market));
        originARM.removeMarket(address(market));

        // Assertions after
        assertEq(originARM.supportedMarkets(address(market)), false);
    }

    function test_SetActiveMarket_NoPreviousMarket()
        public
        forceAvailableAssetsToZero
        addMarket(address(market))
        asGovernor
    {
        // Assertions before
        assertEq(originARM.activeMarket(), address(0));

        vm.expectEmit(address(originARM));
        emit AbstractARM.ActiveMarketUpdated(address(market));
        originARM.setActiveMarket(address(market));

        // Assertions after
        assertEq(originARM.activeMarket(), address(market));
    }

    function test_SetActiveMarket_ToZero()
        public
        forceAvailableAssetsToZero
        addMarket(address(market))
        setActiveMarket(address(market))
        asGovernor
    {
        // Assertions before
        assertEq(originARM.activeMarket(), address(market));

        vm.expectEmit(address(originARM));
        emit AbstractARM.ActiveMarketUpdated(address(0));
        originARM.setActiveMarket(address(0));

        // Assertions after
        assertEq(originARM.activeMarket(), address(0));
    }

    function test_SetActiveMarket_WithPreviousMarket_Empty()
        public
        forceAvailableAssetsToZero
        addMarket(address(market))
        setActiveMarket(address(market))
        addMarket(address(market2))
        asGovernor
    {
        // Assertions before
        assertEq(originARM.activeMarket(), address(market));

        vm.expectEmit(address(originARM));
        emit AbstractARM.ActiveMarketUpdated(address(market2));
        originARM.setActiveMarket(address(market2));

        // Assertions after
        assertEq(originARM.activeMarket(), address(market2));
    }

    function test_SetActiveMarket_WithPreviousMarket_NonEmpty_NoShares()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        addMarket(address(market2))
        asGovernor
    {
        // Assertions before
        assertEq(originARM.activeMarket(), address(market));

        vm.expectEmit(address(originARM));
        emit AbstractARM.ActiveMarketUpdated(address(market2));
        originARM.setActiveMarket(address(market2));

        // Assertions after
        assertEq(originARM.activeMarket(), address(market2));
    }

    function test_SetActiveMarket_WithPreviousMarket_NonEmpty_WithShares()
        public
        deposit(alice, DEFAULT_AMOUNT)
        setARMBuffer(0)
        addMarket(address(market))
        setActiveMarket(address(market))
        addMarket(address(market2))
        asGovernor
    {
        // Assertions before
        assertEq(originARM.activeMarket(), address(market));

        vm.expectEmit(address(originARM));
        emit AbstractARM.ActiveMarketUpdated(address(market2));
        originARM.setActiveMarket(address(market2));

        // Assertions after
        assertEq(originARM.activeMarket(), address(market2));
    }

    function test_SetActiveMarket_ToPreviousMarket()
        public
        addMarket(address(market))
        setActiveMarket(address(market))
        addMarket(address(market2))
        asGovernor
    {
        // Assertions before
        assertEq(originARM.activeMarket(), address(market));

        originARM.setActiveMarket(address(market));

        // Assertions after
        assertEq(originARM.activeMarket(), address(market));
    }
}
