/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Harvester} from "contracts/Harvester.sol";
import {Fork_Shared_Test} from "test/fork/Harvester/shared/Shared.sol";

contract Fork_Concrete_Harvester_Swap_Test_ is Fork_Shared_Test {
    address public constant OS_WHALE = 0x9F0dF7799f6FDAd409300080cfF680f5A23df4b1;

    function test_do_a_swap_with_magpie() public {
        vm.prank(OS_WHALE);
        os.transfer(address(harvester), 1 ether);

        // Mock oracle quote to 1 ether
        vm.mockCall(oracle, abi.encodeWithSignature("price(address)"), abi.encode(1 ether));

        bytes memory data = getMagPieQuote({
            from: "OS",
            to: "WS",
            amount: 1,
            slippage: 0,
            swapper: address(harvester),
            recipient: harvester.rewardRecipient()
        });

        vm.startPrank(harvester.owner());
        harvester.swap(Harvester.SwapPlatform.Magpie, address(os), 1e18, data);
        vm.stopPrank();
    }

    function getMagPieQuote(
        string memory from,
        string memory to,
        uint256 amount,
        uint256 slippage,
        address swapper,
        address recipient
    ) public returns (bytes memory) {
        // npx hardhat magpieQuote --network sonic
        string[] memory inputs = new string[](17);
        inputs[0] = "npx";
        inputs[1] = "hardhat";
        inputs[2] = "magpieQuote";
        inputs[3] = "--network";
        inputs[4] = "sonic";
        inputs[5] = "--from";
        inputs[6] = from;
        inputs[7] = "--to";
        inputs[8] = to;
        inputs[9] = "--amount";
        inputs[10] = vm.toString(amount);
        inputs[11] = "--slippage";
        inputs[12] = vm.toString(slippage);
        inputs[13] = "--swapper";
        inputs[14] = vm.toString(swapper);
        inputs[15] = "--recipient";
        inputs[16] = vm.toString(recipient);

        return abi.decode(vm.ffi(inputs), (bytes));
    }
}
