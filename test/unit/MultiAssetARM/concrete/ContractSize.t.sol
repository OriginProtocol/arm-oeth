// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {MultiAssetARM} from "contracts/MultiAssetARM.sol";

contract Unit_MultiAssetARM_ContractSize_Test is Test {
    /// @notice EIP-170 maximum deployed runtime code size: 24,576 bytes = 24 KiB.
    uint256 internal constant EIP_170_RUNTIME_SIZE_LIMIT = 24_576;

    function test_RuntimeCodeSize_DoesNotExceedEip170Limit() public {
        MockERC20 liquidity = new MockERC20("Liquidity", "LIQ", 6);
        MultiAssetARM implementation = new MultiAssetARM({
            _liquidityAsset: address(liquidity),
            _claimDelay: 10 minutes,
            _minSharesToRedeem: 1e6,
            _allocateThreshold: 100e6
        });

        assertLe(address(implementation).code.length, EIP_170_RUNTIME_SIZE_LIMIT, "MultiAssetARM exceeds EIP-170");
    }
}
