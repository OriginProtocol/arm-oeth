// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Base_Test_} from "test/Base.sol";

abstract contract Helpers is Base_Test_ {
    function getFlyTradeQuote(
        string memory from,
        string memory to,
        uint256 amount,
        string memory slippage,
        address swapper,
        address recipient
    ) public returns (bytes memory) {
        // npx hardhat flyTradeQuote --network sonic
        string[] memory inputs = new string[](17);
        inputs[0] = "npx";
        inputs[1] = "hardhat";
        inputs[2] = "flyTradeQuote";
        inputs[3] = "--network";
        inputs[4] = "sonic";
        inputs[5] = "--from";
        inputs[6] = from;
        inputs[7] = "--to";
        inputs[8] = to;
        inputs[9] = "--amount";
        inputs[10] = vm.toString(amount);
        inputs[11] = "--slippage";
        inputs[12] = slippage;
        inputs[13] = "--swapper";
        inputs[14] = vm.toString(swapper);
        inputs[15] = "--recipient";
        inputs[16] = vm.toString(recipient);
        bytes memory response = vm.ffi(inputs);

        // The flyTradeQuote hardhat task emits this sentinel when the upstream
        // FlyTrade API returns Cloudflare error 525 (SSL handshake failure).
        // In that case, skip the test instead of failing on flaky external
        // infrastructure. Any other upstream error still surfaces as an FFI
        // revert and fails the test.
        if (keccak256(response) == keccak256(hex"c10ad11ae525")) {
            vm.skip(true);
        }

        return abi.decode(response, (bytes));
    }
}
