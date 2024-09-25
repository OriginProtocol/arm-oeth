// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Vm} from "forge-std/Vm.sol";

import {Mainnet} from "contracts/utils/Addresses.sol";

/// @notice This contract should be used to mock calls to other contracts.
library MockCall {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function mockCallDripperCollect(address dripper) external {
        vm.mockCall({callee: dripper, data: abi.encodeWithSignature("collect()"), returnData: abi.encode(true)});
    }

    function mockCallLidoClaimWithdrawals(address target) external {
        vm.mockFunction({
            callee: Mainnet.LIDO_WITHDRAWAL,
            target: target,
            data: abi.encodeWithSignature("claimWithdrawals(uint256[],uint256[])")
        });
    }
}

contract MockLidoWithdraw {
    receive() external payable {}

    address public lidoFixedPriceMulltiLpARM;

    constructor(address _lidoFixedPriceMulltiLpARM) {
        lidoFixedPriceMulltiLpARM = _lidoFixedPriceMulltiLpARM;
    }

    function claimWithdrawals(uint256[] memory, uint256[] memory) external {
        (bool success,) = address(lidoFixedPriceMulltiLpARM).call{value: address(this).balance}("");
        require(success, "MockLidoWithdraw: ETH transfer failed");
    }
}
