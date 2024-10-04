// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {AbstractARM} from "./AbstractARM.sol";
import {IERC20, IStETHWithdrawal, IWETH} from "./Interfaces.sol";

/**
 * @title Lido (stETH) Automated Redemption Manager (ARM)
 * @dev This implementation supports multiple Liquidity Providers (LPs) with single buy and sell prices.
 * It also integrates to a CapManager contract that caps the amount of assets a liquidity provider
 * can deposit and caps the ARM's total assets.
 * A performance fee is also collected on increases in the ARM's total assets.
 * @author Origin Protocol Inc
 */
contract LidoARM is Initializable, AbstractARM {
    /// @notice The address of the Lido stETH token
    IERC20 public immutable steth;
    /// @notice The address of the Wrapped ETH (WETH) token
    IWETH public immutable weth;
    /// @notice The address of the Lido Withdrawal Queue contract
    IStETHWithdrawal public immutable withdrawalQueue;

    /// @notice The amount of stETH in the Lido Withdrawal Queue
    uint256 public lidoWithdrawalQueueAmount;

    /// @param _steth The address of the stETH token
    /// @param _weth The address of the WETH token
    /// @param _lidoWithdrawalQueue The address of the Lido's withdrawal queue contract
    constructor(address _steth, address _weth, address _lidoWithdrawalQueue) AbstractARM(_weth, _steth, _weth) {
        steth = IERC20(_steth);
        weth = IWETH(_weth);
        withdrawalQueue = IStETHWithdrawal(_lidoWithdrawalQueue);
    }

    /// @notice Initialize the storage variables stored in the proxy contract.
    /// The deployer that calls initialize has to approve the this ARM's proxy contract to transfer 1e12 WETH.
    /// @param _name The name of the liquidity provider (LP) token.
    /// @param _symbol The symbol of the liquidity provider (LP) token.
    /// @param _operator The address of the account that can request and claim Lido withdrawals.
    /// @param _fee The performance fee that is collected by the feeCollector measured in basis points (1/100th of a percent).
    /// 10,000 = 100% performance fee
    /// 1,500 = 15% performance fee
    /// @param _feeCollector The account that can collect the performance fee
    /// @param _capManager The address of the CapManager contract
    function initialize(
        string calldata _name,
        string calldata _symbol,
        address _operator,
        uint256 _fee,
        address _feeCollector,
        address _capManager
    ) external initializer {
        _initARM(_operator, _name, _symbol, _fee, _feeCollector, _capManager);

        // Approve the Lido withdrawal queue contract. Used for redemption requests.
        steth.approve(address(withdrawalQueue), type(uint256).max);
    }

    /**
     * @dev Due to internal stETH mechanics required for rebasing support, in most cases stETH transfers are performed
     * for the value of 1 wei less than passed to transfer method. Larger transfer amounts can be 2 wei less.
     *
     * The MultiLP implementation ensures any WETH reserved for the withdrawal queue is not used in swaps from stETH to WETH.
     */
    function _transferAsset(address asset, address to, uint256 amount) internal override {
        // Add 2 wei if transferring stETH
        uint256 transferAmount = asset == address(steth) ? amount + 2 : amount;

        super._transferAsset(asset, to, transferAmount);
    }

    /**
     * @notice Request a stETH for ETH withdrawal.
     * Reference: https://docs.lido.fi/contracts/withdrawal-queue-erc721/
     * Note: There is a 1k amount limit. Caller should split large withdrawals in chunks of less or equal to 1k each.)
     */
    function requestStETHWithdrawalForETH(uint256[] memory amounts)
        external
        onlyOperatorOrOwner
        returns (uint256[] memory requestIds)
    {
        requestIds = withdrawalQueue.requestWithdrawals(amounts, address(this));

        // Sum the total amount of stETH being withdraw
        uint256 totalAmountRequested = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmountRequested += amounts[i];
        }

        // Increase the Ether outstanding from the Lido Withdrawal Queue
        lidoWithdrawalQueueAmount += totalAmountRequested;
    }

    /**
     * @notice Claim the ETH owed from the redemption requests and convert it to WETH.
     * Before calling this method, caller should check on the request NFTs to ensure the withdrawal was processed.
     */
    function claimStETHWithdrawalForWETH(uint256[] memory requestIds) external onlyOperatorOrOwner {
        uint256 etherBefore = address(this).balance;

        // Claim the NFTs for ETH.
        uint256 lastIndex = withdrawalQueue.getLastCheckpointIndex();
        uint256[] memory hintIds = withdrawalQueue.findCheckpointHints(requestIds, 1, lastIndex);
        withdrawalQueue.claimWithdrawals(requestIds, hintIds);

        uint256 etherAfter = address(this).balance;

        // Reduce the Ether outstanding from the Lido Withdrawal Queue
        lidoWithdrawalQueueAmount -= etherAfter - etherBefore;

        // Wrap all the received ETH to WETH.
        weth.deposit{value: etherAfter}();
    }

    /**
     * @dev Calculates the amount of stETH in the Lido Withdrawal Queue.
     */
    function _externalWithdrawQueue() internal view override returns (uint256) {
        return lidoWithdrawalQueueAmount;
    }

    // This method is necessary for receiving the ETH claimed as part of the withdrawal.
    receive() external payable {}
}
