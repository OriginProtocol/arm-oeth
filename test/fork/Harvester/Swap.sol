/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Sonic} from "contracts/utils/Addresses.sol";
import {SonicHarvester} from "contracts/SonicHarvester.sol";

import {Fork_Shared_Test} from "test/fork/Harvester/shared/Shared.sol";

contract Fork_Concrete_Harvester_Swap_Test_ is Fork_Shared_Test {
    address public constant OS_WHALE = 0x9F0dF7799f6FDAd409300080cfF680f5A23df4b1;

    ////////////////////////////////////////////////////
    /// --- SETUP
    ////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();

        // Mock call on the oracle to return 1:1
        vm.mockCall(oracle, abi.encodeWithSignature("price(address)"), abi.encode(1 ether));
    }

    ////////////////////////////////////////////////////
    /// --- REVERTS
    ////////////////////////////////////////////////////
    function test_RevertWhen_Swap_Because_InvalidSwapRecipient() public {
        bytes memory data = getFlyTradeQuote({
            from: "OS",
            to: "WS",
            amount: 1,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: deployer
        });

        vm.expectRevert(
            abi.encodeWithSelector(SonicHarvester.InvalidSwapRecipient.selector, deployer), address(harvester)
        );
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), 1e18, data);
    }

    function test_RevertWhen_Swap_Because_InvalidFromAsset() public {
        bytes memory data = getFlyTradeQuote({
           from: "OS",
           to: "WS",
           amount: 1,
           slippage: "0.01",
           swapper: address(harvester),
           recipient: address(harvester)
        });

        vm.expectRevert(
            abi.encodeWithSelector(SonicHarvester.InvalidFromAsset.selector, address(os)), address(harvester)
        );
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(ws), 1e18, data);
    }

    function test_RevertWhen_Swap_Because_InvalidToAsset() public {
        bytes memory data = getFlyTradeQuote({
            from: "OS",
            to: "SILO",
            amount: 1,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: address(harvester)
        });

        vm.expectRevert(abi.encodeWithSelector(SonicHarvester.InvalidToAsset.selector, Sonic.SILO), address(harvester));
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), 1e18, data);
    }

    function test_RevertWhen_Swap_Because_InvalidFromAssetAmount() public {
        bytes memory data = getFlyTradeQuote({
           from: "OS",
           to: "WS",
           amount: 1,
           slippage: "0.01",
           swapper: address(harvester),
           recipient: address(harvester)
        });

        vm.expectRevert(
            abi.encodeWithSelector(SonicHarvester.InvalidFromAssetAmount.selector, 1 ether), address(harvester)
        );
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), 2e18, data);
    }

    function test_RevertWhen_Swap_Because_SlippageError() public {
        vm.prank(OS_WHALE);
        os.transfer(address(harvester), 1 ether);

        bytes memory data = getFlyTradeQuote({
            from: "OS",
            to: "WS",
            amount: 1,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: address(harvester)
        });

        // Mock call on the oracle to return 2:1
        vm.mockCall(oracle, abi.encodeWithSignature("price(address)"), abi.encode(2 ether));
        // As this is not easy to have the value returned from `swapWithMagpieSignature` we do a partialRevert (i.e. without arguments)
        vm.expectPartialRevert(SonicHarvester.SlippageError.selector);
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), 1e18, data);
    }

    ////////////////////////////////////////////////////
    /// --- TESTS
    ////////////////////////////////////////////////////
    function test_Swap_WithMagpie_WithOracle() public {
        vm.prank(OS_WHALE);
        os.transfer(address(harvester), 1 ether);

        // Get the quote from the API
        bytes memory data = getFlyTradeQuote({
            from: "OS",
            to: "WS",
            amount: 1,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: address(harvester)
        });

        uint256 balanceOSBefore = os.balanceOf(address(harvester));
        uint256 balanceWSBefore = ws.balanceOf(operator);
        assertGe(balanceOSBefore, 1 ether, "Balance of OS before swap should be >= 1");

        vm.startPrank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), 1e18, data);
        vm.stopPrank();
        uint256 balanceOSAfter = os.balanceOf(address(harvester));
        uint256 balanceWSAfter = ws.balanceOf(operator);

        assertEq(balanceOSAfter, 0, "Balance of OS after swap should be 0");
        assertApproxEqRel(balanceWSAfter - balanceWSBefore, 1 ether, 1e16, "Balance of WS after swap should be 1");
    }

    function test_Swap_WithMagpie_WithoutOracle() public {
        vm.prank(OS_WHALE);
        os.transfer(address(harvester), 1 ether);

        // Get the quote from the API
        bytes memory data = getFlyTradeQuote({
            from: "OS",
            to: "WS",
            amount: 1,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: address(harvester)
        });

        vm.prank(governor);
        harvester.setPriceProvider(address(0));

        uint256 balanceOSBefore = os.balanceOf(address(harvester));
        uint256 balanceWSBefore = ws.balanceOf(operator);
        assertGe(balanceOSBefore, 1 ether, "Balance of OS before swap should be >= 1");

        vm.startPrank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), 1e18, data);
        vm.stopPrank();
        uint256 balanceOSAfter = os.balanceOf(address(harvester));
        uint256 balanceWSAfter = ws.balanceOf(address(harvester));

        assertEq(balanceOSAfter, 0, "Balance of OS after swap should be 0");
        assertApproxEqRel(balanceWSAfter - balanceWSBefore, 1 ether, 1e16, "Balance of WS after swap should be 1");
    }
}
