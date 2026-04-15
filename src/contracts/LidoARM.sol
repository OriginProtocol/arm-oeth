// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {AbstractMultiAssetARM} from "./AbstractMultiAssetARM.sol";
import {IERC20, IStETHWithdrawal, IWETH} from "./Interfaces.sol";

/**
 * @title Lido Automated Redemption Manager (ARM)
 * @notice Multi-asset ARM for `stETH` and `wstETH` liquidity against `WETH`.
 */
contract LidoARM is Initializable, AbstractMultiAssetARM {
    IERC20 public immutable steth;
    IWETH public immutable weth;
    IStETHWithdrawal public immutable lidoWithdrawalQueue;

    constructor(
        address _steth,
        address _weth,
        address _lidoWithdrawalQueue,
        uint256 _claimDelay,
        uint256 _minSharesToRedeem,
        int256 _allocateThreshold
    ) AbstractMultiAssetARM(_weth, _claimDelay, _minSharesToRedeem, _allocateThreshold) {
        steth = IERC20(_steth);
        weth = IWETH(_weth);
        lidoWithdrawalQueue = IStETHWithdrawal(_lidoWithdrawalQueue);

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

    receive() external payable {}
}
