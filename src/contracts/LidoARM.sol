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
    IStETHWithdrawal public immutable lidoWithdrawalQueue;

    /// @notice The amount of stETH in the Lido Withdrawal Queue
    uint256 public lidoWithdrawalQueueAmount;

    event RequestLidoWithdrawals(uint256[] amounts, uint256[] requestIds);
    event ClaimLidoWithdrawals(uint256[] requestIds);

    /// @param _steth The address of the stETH token
    /// @param _weth The address of the WETH token
    /// @param _lidoWithdrawalQueue The address of the Lido's withdrawal queue contract
    /// @param _claimDelay The delay in seconds before a user can claim a redeem from the request
    constructor(address _steth, address _weth, address _lidoWithdrawalQueue, uint256 _claimDelay)
        AbstractARM(_weth, _steth, _weth, _claimDelay)
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
        uint256 etherBefore = address(this).balance;

        // Claim the NFTs for ETH.
        lidoWithdrawalQueue.claimWithdrawals(requestIds, hintIds);

        uint256 etherAfter = address(this).balance;

        // Reduce the Ether outstanding from the Lido Withdrawal Queue
        lidoWithdrawalQueueAmount -= etherAfter - etherBefore;

        // Wrap all the received ETH to WETH.
        weth.deposit{value: etherAfter}();

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
