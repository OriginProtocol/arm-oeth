// SPDX-License-Identifier: BUSL-1.1
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
    IStETHWithdrawal public immutable lidoWithdrawalQueue;

    /// @notice The amount of stETH in the Lido Withdrawal Queue
    uint256 public lidoWithdrawalQueueAmount;

    /// @notice stores the requested amount for each Lido withdrawal
    mapping(uint256 id => uint256 amount) public lidoWithdrawalRequests;

    event RequestLidoWithdrawals(uint256[] amounts, uint256[] requestIds);
    event ClaimLidoWithdrawals(uint256[] requestIds);
    event RegisterLidoWithdrawalRequests(uint256[] requestIds, uint256 totalAmountRequested);

    /// @param _steth The address of the stETH token
    /// @param _weth The address of the WETH token
    /// @param _lidoWithdrawalQueue The address of the Lido's withdrawal queue contract
    /// @param _claimDelay The delay in seconds before a user can claim a redeem from the request
    constructor(address _steth, address _weth, address _lidoWithdrawalQueue, uint256 _claimDelay)
        AbstractARM(_weth, _steth, _weth, _claimDelay, 0, 0)
    {
        steth = IERC20(_steth);
        weth = IWETH(_weth);
        lidoWithdrawalQueue = IStETHWithdrawal(_lidoWithdrawalQueue);

        _disableInitializers();
    }

    /// @notice Initialize the storage variables stored in the proxy contract.
    /// The deployer that calls initialize has to approve the ARM's proxy contract to transfer 1e12 WETH.
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
        steth.approve(address(lidoWithdrawalQueue), type(uint256).max);
    }

    /**
     * @notice Register the Lido withdrawal requests to the ARM contract.
     * This can only be called once by the contract Owner.
     */
    function registerLidoWithdrawalRequests() external reinitializer(2) onlyOwner {
        uint256 totalAmountRequested = 0;
        // Get all the ARM's outstanding withdrawal requests
        uint256[] memory requestIds = IStETHWithdrawal(lidoWithdrawalQueue).getWithdrawalRequests(address(this));
        // Get the status of all the withdrawal requests. eg amount, owner, claimed status
        IStETHWithdrawal.WithdrawalRequestStatus[] memory statuses =
            IStETHWithdrawal(lidoWithdrawalQueue).getWithdrawalStatus(requestIds);

        for (uint256 i = 0; i < requestIds.length; i++) {
            // The following should always be true given the requestIds came from calling getWithdrawalRequests
            require(statuses[i].isClaimed == false, "LidoARM: already claimed");
            require(statuses[i].owner == address(this), "LidoARM: not owner");

            // Store the amount of stETH of each Lido withdraw request
            lidoWithdrawalRequests[requestIds[i]] = statuses[i].amountOfStETH;
            totalAmountRequested += statuses[i].amountOfStETH;
        }

        require(totalAmountRequested == lidoWithdrawalQueueAmount, "LidoARM: missing requests");

        emit RegisterLidoWithdrawalRequests(requestIds, totalAmountRequested);
    }

    /**
     * @notice Request a stETH for ETH withdrawal.
     * Reference: https://docs.lido.fi/contracts/withdrawal-queue-erc721/
     * Note: There is a 1k amount limit. Caller should split large withdrawals in chunks of less or equal to 1k each.)
     */
    function requestLidoWithdrawals(uint256[] calldata amounts)
        external
        onlyOperatorOrOwner
        returns (uint256[] memory requestIds)
    {
        requestIds = lidoWithdrawalQueue.requestWithdrawals(amounts, address(this));

        // Sum the total amount of stETH being withdraw
        uint256 totalAmountRequested = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmountRequested += amounts[i];

            // Store the amount of each withdrawal request
            lidoWithdrawalRequests[requestIds[i]] = amounts[i];
        }

        // Increase the Ether outstanding from the Lido Withdrawal Queue
        lidoWithdrawalQueueAmount += totalAmountRequested;

        emit RequestLidoWithdrawals(amounts, requestIds);
    }

    /**
     * @notice Claim the ETH owed from the redemption requests and convert it to WETH.
     * Before calling this method, caller should check on the request NFTs to ensure the withdrawal was processed.
     * @param requestIds The request IDs of the withdrawal requests.
     * @param hintIds The hint IDs of the withdrawal requests.
     * Call `findCheckpointHints` on the Lido withdrawal queue contract to get the hint IDs.
     */
    function claimLidoWithdrawals(uint256[] calldata requestIds, uint256[] calldata hintIds) external {
        // Claim the NFTs for ETH.
        lidoWithdrawalQueue.claimWithdrawals(requestIds, hintIds);

        // Reduce the amount outstanding from the Lido Withdrawal Queue.
        // The amount of ETH claimed from the Lido Withdrawal Queue can be less than the requested amount
        // in the event of a mass slashing event of Lido validators.
        uint256 totalAmountRequested = 0;
        for (uint256 i = 0; i < requestIds.length; i++) {
            // Read the requested amount from storage
            uint256 requestAmount = lidoWithdrawalRequests[requestIds[i]];

            // Validate the request came from this Lido ARM contract and not
            // transferred in from another account.
            require(requestAmount > 0, "LidoARM: invalid request");

            totalAmountRequested += requestAmount;
        }

        // Store the reduced outstanding withdrawals from the Lido Withdrawal Queue
        if (lidoWithdrawalQueueAmount < totalAmountRequested) {
            // This can happen if a Lido withdrawal request was transferred to the ARM contract
            lidoWithdrawalQueueAmount = 0;
        } else {
            lidoWithdrawalQueueAmount -= totalAmountRequested;
        }

        // Wrap all the received ETH to WETH.
        weth.deposit{value: address(this).balance}();

        emit ClaimLidoWithdrawals(requestIds);
    }

    /**
     * @dev Calculates the amount of stETH in the Lido Withdrawal Queue.
     */
    function _externalWithdrawQueue() internal view override returns (uint256) {
        return lidoWithdrawalQueueAmount;
    }

    /// @notice This payable method is necessary for receiving ETH claimed from the Lido withdrawal queue.
    receive() external payable {}
}
