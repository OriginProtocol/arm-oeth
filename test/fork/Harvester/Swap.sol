/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Sonic} from "contracts/utils/Addresses.sol";
import {SonicHarvester} from "contracts/SonicHarvester.sol";

import {Fork_Shared_Test} from "test/fork/Harvester/shared/Shared.sol";

contract Fork_Concrete_Harvester_Swap_Test_ is Fork_Shared_Test {
    address public constant OS_WHALE = 0x9F0dF7799f6FDAd409300080cfF680f5A23df4b1;
    uint256 public constant FLYTRADE_FEES_PCT = 0.0001 ether; // 0.01% fee
    uint256 public constant DEFAULT_AMOUNT_FLYTRADE = DEFAULT_AMOUNT / 1e18;
    uint256 public constant DEFAULT_FEES = DEFAULT_AMOUNT * FLYTRADE_FEES_PCT / 1e18;
    uint256 public constant DEFAULT_AMOUNT_MINUS_FEES = DEFAULT_AMOUNT - (1e18 * FLYTRADE_FEES_PCT / 1e18);

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
    function test_RevertWhen_Swap_Because_FeesTooHigh() public {
        uint256 fakeFees = DEFAULT_AMOUNT * FLYTRADE_FEES_PCT * 200 / 1e18; // 2% fees - x200 default flytrade fees
        vm.expectRevert(abi.encodeWithSelector(SonicHarvester.FeesTooHigh.selector, fakeFees), address(harvester));
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), DEFAULT_AMOUNT - fakeFees, fakeFees, hex"");
    }

    function test_RevertWhen_Swap_Because_InvalidSwapRecipient() public {
        bytes memory data = getFlyTradeQuote({
            from: "OS",
            to: "WS",
            amount: DEFAULT_AMOUNT_FLYTRADE,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: deployer
        });
        vm.expectRevert(
            abi.encodeWithSelector(SonicHarvester.InvalidSwapRecipient.selector, deployer), address(harvester)
        );
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), DEFAULT_AMOUNT_MINUS_FEES, DEFAULT_FEES, data);
    }

    function test_RevertWhen_Swap_Because_InvalidFromAsset() public {
        bytes memory data = getFlyTradeQuote({
            from: "OS",
            to: "WS",
            amount: DEFAULT_AMOUNT_FLYTRADE,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: address(harvester)
        });
        vm.expectRevert(
            abi.encodeWithSelector(SonicHarvester.InvalidFromAsset.selector, address(os)), address(harvester)
        );
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(ws), DEFAULT_AMOUNT_MINUS_FEES, DEFAULT_FEES, data);
    }

    function test_RevertWhen_Swap_Because_InvalidToAsset() public {
        bytes memory data = getFlyTradeQuote({
            from: "OS",
            to: "SILO",
            amount: DEFAULT_AMOUNT_FLYTRADE,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: address(harvester)
        });
        vm.expectRevert(abi.encodeWithSelector(SonicHarvester.InvalidToAsset.selector, Sonic.SILO), address(harvester));
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), DEFAULT_AMOUNT_MINUS_FEES, DEFAULT_FEES, data);
    }

    function test_RevertWhen_Swap_Because_InvalidFromAssetAmount() public {
        bytes memory data = getFlyTradeQuote({
            from: "OS",
            to: "WS",
            amount: DEFAULT_AMOUNT_FLYTRADE,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: address(harvester)
        });
        vm.expectRevert(
            abi.encodeWithSelector(SonicHarvester.InvalidFromAssetAmount.selector, DEFAULT_AMOUNT_MINUS_FEES),
            address(harvester)
        );
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), 2 * DEFAULT_AMOUNT_FLYTRADE, 0, data);
    }

    function test_RevertWhen_Swap_Because_SlippageError() public {
        // This test is failing atm due to changes on FlyTrade Quote. AmountIn is now the amount minus the fees.
        // This breaks our SonicHarvester::swap function, because the ammount approved is the amount passed as amountIn,
        // but this is missing the fees, which brings an "Allowance exceeded" error.
        vm.prank(OS_WHALE);
        os.transfer(address(harvester), 1 ether);

        bytes memory data = getFlyTradeQuote({
            from: "OS",
            to: "WS",
            amount: DEFAULT_AMOUNT_FLYTRADE,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: address(harvester)
        });
        // Mock call on the oracle to return 2:1
        vm.mockCall(oracle, abi.encodeWithSignature("price(address)"), abi.encode(2 ether));
        // As this is not easy to have the value returned from `swapWithMagpieSignature` we do a partialRevert (i.e. without arguments)
        vm.expectPartialRevert(SonicHarvester.SlippageError.selector);
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), DEFAULT_AMOUNT_MINUS_FEES, DEFAULT_FEES, data);
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
            amount: DEFAULT_AMOUNT_FLYTRADE,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: address(harvester)
        });

        uint256 balanceOSBefore = os.balanceOf(address(harvester));
        uint256 balanceWSBefore = ws.balanceOf(operator);
        assertGe(balanceOSBefore, 1 ether, "Balance of OS before swap should be >= 1");

        vm.startPrank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), DEFAULT_AMOUNT_MINUS_FEES, DEFAULT_FEES, data);
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
            amount: DEFAULT_AMOUNT_FLYTRADE,
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
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), DEFAULT_AMOUNT_MINUS_FEES, DEFAULT_FEES, data);
        vm.stopPrank();
        uint256 balanceOSAfter = os.balanceOf(address(harvester));
        uint256 balanceWSAfter = ws.balanceOf(address(harvester));

        assertEq(balanceOSAfter, 0, "Balance of OS after swap should be 0");
        assertApproxEqRel(balanceWSAfter - balanceWSBefore, 1 ether, 1e16, "Balance of WS after swap should be 1");
    }
}
