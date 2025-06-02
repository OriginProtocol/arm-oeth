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
        // bytes memory data = getMagPieQuote({
        //    from: "OS",
        //    to: "WS",
        //    amount: 1,
        //    slippage: "0.01",
        //    swapper: address(harvester),
        //    recipient: address(harvester)
        // });

        // This is approx the data that should be return from the call on the API, but to avoid too much API call we store it.
        bytes memory data =
            hex"022b00e08ad159a275aee56fb2334dbb69036e9c7bacee9bb1e25689d55734fd3fffc939c4c3eb52dff8a794039e2fb66102314ce7b64ce5ce3e5183bc94ad38e000d4c000d9f800e2c000e4861f5283f7651f412bc1ff1e49be8c5db0b7e3b34edbd88e96a173d1b4af59c806d2a93cc90ac27d9cd1aa6fd9b9334473a3186072c07a5f9949d56a4bd392821b0000e06837087fc00db0857ea8a1034bf800c00de0b6b3a7640000060300e3128acb08000000000000000000000000fffd8963efd1fc6a506488495d951d5263988d2500000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000014b1e25689d55734fd3fffc939c4c3eb52dff8a7940000000000000000000000000100f00603008a0300e30400f400800c9a698ed5422eae47ce0b4096496b1fa7771d7d00070a000000000000000000000000000000000000000000000000000000000000030197050000020070000206070706000000000000000000000000000000000000000000000000000000c00dd3ebb111c441630301c10500600301e200020a0b00000000000000000000000000000000000000000000000000000000000301f40500800301e2eda49bce2f38d284f839be1f4f2e23e6c7cc7dbd02007002021e0500a000050607080700000000000000000000000000000000000000000000000000000003023b0500800301e20500600200700200480500c002000000ec00f0000000004001740183018307002001b801be000006002001be01c1000008002001eb01f400000700200215021e00000300000232023b0000080020025c02680000030000026802710000";

        vm.expectRevert(
            abi.encodeWithSelector(SonicHarvester.InvalidFromAsset.selector, address(os)), address(harvester)
        );
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(ws), 1e18, data);
    }

    function test_RevertWhen_Swap_Because_InvalidToAsset() public {
        // bytes memory data = getMagPieQuote({
        //    from: "OS",
        //    to: "SILO",
        //    amount: 1,
        //    slippage: "0.01",
        //    swapper: address(harvester),
        //    recipient: address(harvester)
        // });

        // This is approx the data that should be return from the call on the API, but to avoid too much API call we store it.
        bytes memory data =
            hex"03ce02208ad159a275aee56fb2334dbb69036e9c7bacee9bb1e25689d55734fd3fffc939c4c3eb52dff8a79453f753e4b17f4075d6fa2c6909033d224b81e698e000d4c000d9f800e2c000e42284d99e074fe43016941a70f65a621715b8f49cd138bdd15e706f42e3e39aa61bea35432c25575a0dd410e451bc987c69b97c0f37220a316a9ee7932f4d98101c0000e068370937c092ce08503175a5f0f800c00de0b6b3a7640000060300e39f0df7799f6fdad409300080cff680f5a23df4b102005c0200f00300e36e553f6501010d0300e306128acb08f80100000000000000000000000000000000000000000000000000000001000276a400000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000149f0df7799f6fdad409300080cff680f5a23df4b10000000000000000000000000101180603011c05000004011e0080b6d833db433aece6abd8128a61898a219a9c814800070a0000000000000000000000000000000000000000000000000000000000000301c1050040e5da20f15420ad15de0fa650600afc998bbe3955000000000022d473030f116ddee9f6b43ac78ba30201e80201fc05006087517c457761659f9e9834ad367e4d25e0306ba7a4968daf0102190201e802021d0500600300d3286f580df880f001c0f8206dada303ff381b8a2c898b573b6151d15c1659236646248971427b80ce531bdd793e2eb859347e550102400302440300d303008a03024603011c0302490201e803024405006003008a03011c02024b02025f03008a03008a02025f02025f050100ba0876520102ac050100060600000000000000000000000000000000000000000000000000000001000276a400000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000001429219dd400f2bf60e5a23d13be72b486d40388940000000000000000000000000101180603011c0501200402b800803b7e60fd9cbd290338b01bdccccbf0edb3c841da0301c1050160020070000206070706000000000000000000000000000000000000000000000000000000c09449a622753104b40303640501a003038500020a0b00000000000000000000000000000000000000000000000000000000000303970501c0030385eda49bce2f38d284f839be1f4f2e23e6c7cc7dbd0200700203c10501e00005060708070000000000000000000000000000000000000000000000000000000303de0501c00303850501a002007002004805020002000000ec00f000000100000104010d00000000200111011800f0000040019e01ad01ad07002001e201e800000100000210021900000000000231024001fc0000a0027302a3021d01000002a302ac000000002002b002b8025f000040033803470347070020035b03610000060020036103640000080020038e0397000007002003b803c1000003000003d503de000008002003ff040b0000030000040b04140000";

        vm.expectRevert(abi.encodeWithSelector(SonicHarvester.InvalidToAsset.selector, Sonic.SILO), address(harvester));
        vm.prank(governor);
        harvester.swap(SonicHarvester.SwapPlatform.Magpie, address(os), 1e18, data);
    }

    function test_RevertWhen_Swap_Because_InvalidFromAssetAmount() public {
        // bytes memory data = getMagPieQuote({
        //    from: "OS",
        //    to: "WS",
        //    amount: 1,
        //    slippage: "0.01",
        //    swapper: address(harvester),
        //    recipient: address(harvester)
        // });

        // This is approx the data that should be return from the call on the API, but to avoid too much API call we store it.
        bytes memory data =
            hex"022b00e08ad159a275aee56fb2334dbb69036e9c7bacee9bb1e25689d55734fd3fffc939c4c3eb52dff8a794039e2fb66102314ce7b64ce5ce3e5183bc94ad38e000d4c000d9f800e2c000e4da2dc75b6b6509a9729ffbc3f9da91295a53dccce73766b525018b55ab0c471336ecb17f11ba879330b7104e942fba441bb181d060f653eb2ddcf82755f0c33b1c0000e068370a79c00db0861ad23abc54f800c00de0b6b3a7640000060300e3128acb08000000000000000000000000fffd8963efd1fc6a506488495d951d5263988d2500000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000014b1e25689d55734fd3fffc939c4c3eb52dff8a7940000000000000000000000000100f00603008a0300e30400f400800c9a698ed5422eae47ce0b4096496b1fa7771d7d00070a000000000000000000000000000000000000000000000000000000000000030197050000020070000206070706000000000000000000000000000000000000000000000000000000c00dd3ec4ecf2e66500301c10500600301e200020a0b00000000000000000000000000000000000000000000000000000000000301f40500800301e2eda49bce2f38d284f839be1f4f2e23e6c7cc7dbd02007002021e0500a000050607080700000000000000000000000000000000000000000000000000000003023b0500800301e20500600200700200480500c002000000ec00f0000000004001740183018307002001b801be000006002001be01c1000008002001eb01f400000700200215021e00000300000232023b0000080020025c02680000030000026802710000";

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
        bytes memory data = getMagPieQuote({
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
        bytes memory data = getMagPieQuote({
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
