// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {AbstractMultiAssetARM} from "./AbstractMultiAssetARM.sol";

/**
 * @title Multi-base Centrifuge Automated Redemption Manager (ARM)
 * @author Origin Protocol Inc
 */
contract CentrifugeARM is Initializable, AbstractMultiAssetARM {
    constructor(address _liquidityAsset, uint256 _claimDelay, uint256 _minSharesToRedeem, int256 _allocateThreshold)
        AbstractMultiAssetARM(_liquidityAsset, _claimDelay, _minSharesToRedeem, _allocateThreshold)
    {
        _disableInitializers();
    }

    function initialize(
        string calldata _name,
        string calldata _symbol,
        address _operator,
        uint256 _fee,
        address _feeCollector,
        address _capManager
    ) external initializer {
        _initARM(_operator, _name, _symbol, _fee, _feeCollector, _capManager);
    }
}
