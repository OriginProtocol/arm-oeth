// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Vm} from "forge-std/Vm.sol";

import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {ARMAdapterLib} from "contracts/libraries/ARMAdapterLib.sol";

/// @title ARM deployment helper
/// @notice Deploys ARMAdapterLib and MultiAssetARM implementations linked to a specific library instance.
/// @dev Keeps unlinked MultiAssetARM creation bytecode out of dynamically loaded deployment scripts.
library ARMDeploymentHelper {
    /// @dev Solidity's link placeholder for contracts/libraries/ARMAdapterLib.sol:ARMAdapterLib.
    string internal constant ARM_ADAPTER_LIB_PLACEHOLDER = "__$13fc881d3fc475fdd3ac87119115f1ebd2$__";

    struct MultiAssetARMConfig {
        /// @notice Asset used for LP deposits, redeem claims, and base-asset quote pricing.
        address liquidityAsset;
        /// @notice Delay before an LP redeem request can be claimed. For example, 600 = 10 minutes.
        uint256 claimDelay;
        /// @notice Minimum market shares redeemed during allocation. For example, 1e6 = 1 share for a 6-decimal market.
        uint256 minSharesToRedeem;
        /// @notice Minimum excess liquidity moved during allocation. For example, 100e6 = 100 units for a 6-decimal asset.
        int256 allocateThreshold;
    }

    function deployARMAdapterLib() internal returns (address adapterLib) {
        bytes memory creationCode = type(ARMAdapterLib).creationCode;
        assembly ("memory-safe") {
            adapterLib := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(adapterLib != address(0), "ARMAdapterLib deployment failed");
    }

    function deployMultiAssetARM(
        Vm vm,
        string memory projectRoot,
        address adapterLib,
        MultiAssetARMConfig memory config
    ) internal returns (MultiAssetARM armImpl) {
        string memory artifactPath = string.concat(projectRoot, "/out/MultiAssetARM.sol/MultiAssetARM.json");
        string memory artifact = vm.readFile(artifactPath);
        string memory creationCodeHex = vm.parseJsonString(artifact, ".bytecode.object");
        string memory linkedCreationCodeHex =
            vm.replace(creationCodeHex, ARM_ADAPTER_LIB_PLACEHOLDER, _addressWithoutHexPrefix(vm, adapterLib));
        require(
            keccak256(bytes(linkedCreationCodeHex)) != keccak256(bytes(creationCodeHex)),
            "ARMAdapterLib placeholder not found"
        );

        bytes memory creationCode = abi.encodePacked(
            vm.parseBytes(linkedCreationCodeHex),
            abi.encode(config.liquidityAsset, config.claimDelay, config.minSharesToRedeem, config.allocateThreshold)
        );

        address implementation;
        assembly ("memory-safe") {
            implementation := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(implementation != address(0), "MultiAssetARM deployment failed");
        armImpl = MultiAssetARM(payable(implementation));
    }

    function _addressWithoutHexPrefix(Vm vm, address account) private pure returns (string memory) {
        bytes memory prefixed = bytes(vm.toString(account));
        bytes memory unprefixed = new bytes(40);
        for (uint256 i = 0; i < 40; ++i) {
            unprefixed[i] = prefixed[i + 2];
        }
        return string(unprefixed);
    }
}
