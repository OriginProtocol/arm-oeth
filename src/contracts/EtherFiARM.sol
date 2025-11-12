// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {AbstractARM} from "./AbstractARM.sol";
import {IERC20, IWETH, IEETHWithdrawal, IEETHWithdrawalNFT, IEETHRedemptionManager} from "./Interfaces.sol";

/**
 * @title EtherFi (eETH) Automated Redemption Manager (ARM)
 * @dev This implementation supports multiple Liquidity Providers (LPs) with single buy and sell prices.
 * It also integrates to a CapManager contract that caps the amount of assets a liquidity provider
 * can deposit and caps the ARM's total assets.
 * A performance fee is also collected on increases in the ARM's total assets.
 * @author Origin Protocol Inc
 */
contract EtherFiARM is Initializable, AbstractARM, IERC721Receiver {
    /// @notice The address of the EtherFi eETH token
    IERC20 public immutable eeth;
    /// @notice The address of the Wrapped ETH (WETH) token
    IWETH public immutable weth;
    /// @notice The address of the EtherFi Withdrawal Queue contract
    IEETHWithdrawal public immutable etherfiWithdrawalQueue;
    /// @notice The address of the EtherFi Withdrawal NFT contract
    IEETHWithdrawalNFT public immutable etherfiWithdrawalNFT;
    /// @notice The address of the EtherFi Redemption Manager contract
    IEETHRedemptionManager public immutable etherfiRedemptionManager;

    /// @notice The amount of eETH in the EtherFi Withdrawal Queue
    uint256 public etherfiWithdrawalQueueAmount;

    /// @notice stores the requested amount for each EtherFi withdrawal
    mapping(uint256 id => uint256 amount) public etherfiWithdrawalRequests;

    event RequestEtherFiWithdrawal(uint256 amount, uint256 requestId);
    event ClaimEtherFiWithdrawals(uint256[] requestIds);

    /// @param _eeth The address of the eETH token
    /// @param _weth The address of the WETH token
    /// @param _etherfiWithdrawalQueue The address of the EtherFi's withdrawal queue contract
    /// @param _claimDelay The delay in seconds before a user can claim a redeem from the request
    /// @param _minSharesToRedeem The minimum amount of shares to redeem from the active lending market
    /// @param _allocateThreshold The minimum amount of liquidity assets in excess of the ARM buffer before
    /// the ARM can allocate to a active lending market.
    constructor(
        address _eeth,
        address _weth,
        address _etherfiWithdrawalQueue,
        uint256 _claimDelay,
        uint256 _minSharesToRedeem,
        int256 _allocateThreshold,
        address _etherfiWithdrawalNFT,
        address _etherfiRedemptionManager
    ) AbstractARM(_weth, _eeth, _weth, _claimDelay, _minSharesToRedeem, _allocateThreshold) {
        eeth = IERC20(_eeth);
        weth = IWETH(_weth);
        etherfiWithdrawalQueue = IEETHWithdrawal(_etherfiWithdrawalQueue);
        etherfiWithdrawalNFT = IEETHWithdrawalNFT(_etherfiWithdrawalNFT);
        etherfiRedemptionManager = IEETHRedemptionManager(_etherfiRedemptionManager);

        _disableInitializers();
    }

    /// @notice Initialize the storage variables stored in the proxy contract.
    /// The deployer that calls initialize has to approve the ARM's proxy contract to transfer 1e12 WETH.
    /// @param _name The name of the liquidity provider (LP) token.
    /// @param _symbol The symbol of the liquidity provider (LP) token.
    /// @param _operator The address of the account that can request and claim EtherFi withdrawals.
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

        // Approve the EtherFi withdrawal queue contract. Used for redemption requests.
        eeth.approve(address(etherfiWithdrawalQueue), type(uint256).max);
    }

    /**
     * @notice Request an eETH for ETH withdrawal.
     * Reference: https://etherfi.gitbook.io/etherfi/contracts-and-integrations/how-to
     * @param amount The amount of eETH to withdraw.
     */
    function requestEtherFiWithdrawal(uint256 amount) external onlyOperatorOrOwner returns (uint256 requestId) {
        // Request the withdrawal from the EtherFi Withdrawal Queue.
        requestId = etherfiWithdrawalQueue.requestWithdraw(address(this), amount);

        // Store the requested amount from storage
        etherfiWithdrawalRequests[requestId] = amount;

        // Increase the Ether outstanding from the EtherFi Withdrawal Queue
        etherfiWithdrawalQueueAmount += amount;

        // Emit event for the request
        emit RequestEtherFiWithdrawal(amount, requestId);
    }

    /**
     * @notice Claim the ETH owed from the redemption requests and convert it to WETH.
     * Before calling this method, caller should check on the request NFTs to ensure the withdrawal was processed.
     * @param requestIds The request IDs of the withdrawal requests.
     * Call `findCheckpointHints` on the EtherFi withdrawal queue contract to get the hint IDs.
     */
    function claimEtherFiWithdrawals(uint256[] calldata requestIds) external {
        // Claim the NFTs for ETH.
        etherfiWithdrawalNFT.batchClaimWithdraw(requestIds);

        // Reduce the amount outstanding from the EtherFi Withdrawal Queue.
        // The amount of ETH claimed from the EtherFi Withdrawal Queue can be less than the requested amount
        // in the event of a mass slashing event of EtherFi validators.
        uint256 totalAmountRequested = 0;
        for (uint256 i = 0; i < requestIds.length; i++) {
            // Read the requested amount from storage
            uint256 requestAmount = etherfiWithdrawalRequests[requestIds[i]];

            // Validate the request came from this EtherFi ARM contract and not
            // transferred in from another account.
            require(requestAmount > 0, "EtherFiARM: invalid request");

            totalAmountRequested += requestAmount;
        }

        // Store the reduced outstanding withdrawals from the EtherFi Withdrawal Queue
        if (etherfiWithdrawalQueueAmount < totalAmountRequested) {
            // This can happen if a EtherFi withdrawal request was transferred to the ARM contract
            etherfiWithdrawalQueueAmount = 0;
        } else {
            etherfiWithdrawalQueueAmount -= totalAmountRequested;
        }

        // Wrap all the received ETH to WETH.
        weth.deposit{value: address(this).balance}();

        emit ClaimEtherFiWithdrawals(requestIds);
    }

    /**
     * @dev Calculates the amount of eETH in the EtherFi Withdrawal Queue.
     */
    function _externalWithdrawQueue() internal view override returns (uint256) {
        return etherfiWithdrawalQueueAmount;
    }

    /// @notice This payable method is necessary for receiving ETH claimed from the EtherFi withdrawal queue.
    receive() external payable {}

    /// @notice To be able to receive the NFTs from the EtherFi withdrawal queue contract.
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}
