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
        //bytes memory data = getMagPieQuote({
        //    from: "OS",
        //    to: "WS",
        //    amount: 1,
        //    slippage: "0.01",
        //    swapper: address(harvester),
        //    recipient: deployer
        //});

        // This is approx the data that should be return from the call on the API, but to avoid too much API call we store it.
        bytes memory data =
            hex"022200e0ae0bdc4eeac5e950b67c6819b118761caaf61946b1e25689d55734fd3fffc939c4c3eb52dff8a794039e2fb66102314ce7b64ce5ce3e5183bc94ad38e000d4c000d9f800e2c000e456f053c684bb01e4cf6d46e41bfe7278a8755eae85c327d9304b6b8f8c025edd1e7d859b963e2e666e5fd9975f0cc37999d816a0e3822b32677670e1748bd7991b0000e06811c15fc00dd468809e587294f800c00de0b6b3a7640000060300e3128acb08000000000000000000000000fffd8963efd1fc6a506488495d951d5263988d2500000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000014b1e25689d55734fd3fffc939c4c3eb52dff8a7940000000000000000000000000100f00603008a0300e30400f40080ba2a98f0e04b8d659698c8c891f61a6c604e459e00070a0000000000000000000000000000000000000000000000000000000000000301970500000200700002060707060000000000000000000000000000000000000000000000000000000301c10500600300d800020a0b00000000000000000000000000000000000000000000000000000000000301eb0500800300d8eda49bce2f38d284f839be1f4f2e23e6c7cc7dbd0200700202150500a00005060708070000000000000000000000000000000000000000000000000000000302320500800300d80500600200700200480500c002000000ec00f0000000004001740183018307002001b801be000006002001be01c1000008002001e201eb0000070020020c021500000300000229023200000800200253025f0000030000025f02680000";

        vm.expectRevert(
            abi.encodeWithSelector(SonicHarvester.InvalidSwapRecipient.selector, deployer), address(harvester)
        );
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), 1e18, data);
    }

    function test_RevertWhen_Swap_Because_InvalidFromAsset() public {
        //bytes memory data = getMagPieQuote({
        //    from: "OS",
        //    to: "WS",
        //    amount: 1,
        //    slippage: "0.01",
        //    swapper: address(harvester),
        //    recipient: operator
        //});

        // This is approx the data that should be return from the call on the API, but to avoid too much API call we store it.
        bytes memory data =
            hex"022200e0d1b0c5cbf884fcc27daf9f733739b39fb0b7daa1b1e25689d55734fd3fffc939c4c3eb52dff8a794039e2fb66102314ce7b64ce5ce3e5183bc94ad38e000d4c000d9f800e2c000e41b5c77f6e2bd4168c0d7dfad34c2ac95f0ded36a4a75ee27641974126f74b0c223188745174abbfa4064c20d452b0fe5a62a813978b3e187e420d8c6ef0164b11c0000e06811c272c00dd468809e587294f800c00de0b6b3a7640000060300e3128acb08000000000000000000000000fffd8963efd1fc6a506488495d951d5263988d2500000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000014b1e25689d55734fd3fffc939c4c3eb52dff8a7940000000000000000000000000100f00603008a0300e30400f40080ba2a98f0e04b8d659698c8c891f61a6c604e459e00070a0000000000000000000000000000000000000000000000000000000000000301970500000200700002060707060000000000000000000000000000000000000000000000000000000301c10500600300d800020a0b00000000000000000000000000000000000000000000000000000000000301eb0500800300d8eda49bce2f38d284f839be1f4f2e23e6c7cc7dbd0200700202150500a00005060708070000000000000000000000000000000000000000000000000000000302320500800300d80500600200700200480500c002000000ec00f0000000004001740183018307002001b801be000006002001be01c1000008002001e201eb0000070020020c021500000300000229023200000800200253025f0000030000025f02680000";

        vm.expectRevert(
            abi.encodeWithSelector(SonicHarvester.InvalidFromAsset.selector, address(os)), address(harvester)
        );
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(ws), 1e18, data);
    }

    function test_RevertWhen_Swap_Because_InvalidToAsset() public {
        //bytes memory data = getMagPieQuote({
        //    from: "OS",
        //    to: "SILO",
        //    amount: 1,
        //    slippage: "0.01",
        //    swapper: address(harvester),
        //    recipient: operator
        //});

        // This is approx the data that should be return from the call on the API, but to avoid too much API call we store it.
        bytes memory data =
            hex"022200e0d1b0c5cbf884fcc27daf9f733739b39fb0b7daa1b1e25689d55734fd3fffc939c4c3eb52dff8a79453f753e4b17f4075d6fa2c6909033d224b81e698e000d4c000d9f800e2c000e4fb4bdc018f80fd2c44f64e2064025a562d54ea734c05c94d0e451d7421b6ac41029bdb45cd594c177280e29f17986ffc68862f354827a9363da8312bdd73cd671b0000e06811c5d3c0e11f87681a387882f800c00de0b6b3a7640000060300e3128acb08000000000000000000000000fffd8963efd1fc6a506488495d951d5263988d2500000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000014b1e25689d55734fd3fffc939c4c3eb52dff8a7940000000000000000000000000100f00603008a0300e30400f400802ab09e10f75965ccc369c8b86071f351141dc0a100070a0000000000000000000000000000000000000000000000000000000000000301970500000200700002060707060000000000000000000000000000000000000000000000000000000301c10500600300d800020a0b00000000000000000000000000000000000000000000000000000000000301eb0500800300d8eda49bce2f38d284f839be1f4f2e23e6c7cc7dbd0200700202150500a00005060708070000000000000000000000000000000000000000000000000000000302320500800300d80500600200700200480500c002000000ec00f0000000004001740183018307002001b801be000006002001be01c1000008002001e201eb0000070020020c021500000300000229023200000800200253025f0000030000025f02680000";

        vm.expectRevert(abi.encodeWithSelector(SonicHarvester.InvalidToAsset.selector, Sonic.SILO), address(harvester));
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), 1e18, data);
    }

    function test_RevertWhen_Swap_Because_InvalidFromAssetAmount() public {
        //bytes memory data = getMagPieQuote({
        //    from: "OS",
        //    to: "WS",
        //    amount: 1,
        //    slippage: "0.01",
        //    swapper: address(harvester),
        //    recipient: operator
        //});

        // This is approx the data that should be return from the call on the API, but to avoid too much API call we store it.
        bytes memory data =
            hex"022200e0d1b0c5cbf884fcc27daf9f733739b39fb0b7daa1b1e25689d55734fd3fffc939c4c3eb52dff8a794039e2fb66102314ce7b64ce5ce3e5183bc94ad38e000d4c000d9f800e2c000e4cb5e323d6d329af73893a3ab2ce0482ddc50db00d681af200b388e30f78abddc41a767edd5c48f563582aab35ed401c6f369016c06588ae40ab53c5f162a9b641c0000e06811c686c00dd468809e587294f800c00de0b6b3a7640000060300e3128acb08000000000000000000000000fffd8963efd1fc6a506488495d951d5263988d2500000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000014b1e25689d55734fd3fffc939c4c3eb52dff8a7940000000000000000000000000100f00603008a0300e30400f40080ba2a98f0e04b8d659698c8c891f61a6c604e459e00070a0000000000000000000000000000000000000000000000000000000000000301970500000200700002060707060000000000000000000000000000000000000000000000000000000301c10500600300d800020a0b00000000000000000000000000000000000000000000000000000000000301eb0500800300d8eda49bce2f38d284f839be1f4f2e23e6c7cc7dbd0200700202150500a00005060708070000000000000000000000000000000000000000000000000000000302320500800300d80500600200700200480500c002000000ec00f0000000004001740183018307002001b801be000006002001be01c1000008002001e201eb0000070020020c021500000300000229023200000800200253025f0000030000025f02680000";

        vm.expectRevert(
            abi.encodeWithSelector(SonicHarvester.InvalidFromAssetAmount.selector, 1 ether), address(harvester)
        );
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), 2e18, data);
    }

    function test_RevertWhen_Swap_Because_SlippageError() public {
        vm.prank(OS_WHALE);
        os.transfer(address(harvester), 1 ether);

        bytes memory data = getMagPieQuote({
            from: "OS",
            to: "WS",
            amount: 1,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: operator
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
        bytes memory data = getMagPieQuote({
            from: "OS",
            to: "WS",
            amount: 1,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: operator
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
        bytes memory data = getMagPieQuote({
            from: "OS",
            to: "WS",
            amount: 1,
            slippage: "0.01",
            swapper: address(harvester),
            recipient: operator
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
        uint256 balanceWSAfter = ws.balanceOf(operator);

        assertEq(balanceOSAfter, 0, "Balance of OS after swap should be 0");
        assertApproxEqRel(balanceWSAfter - balanceWSBefore, 1 ether, 1e16, "Balance of WS after swap should be 1");
    }
}
