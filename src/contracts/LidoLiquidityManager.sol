// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableOperable} from "./OwnableOperable.sol";
import {IERC20, IWETH, IStETHWithdrawal} from "./Interfaces.sol";

contract LidoLiquidityManager is OwnableOperable {
    IERC20 public immutable steth;
    IWETH public immutable weth;
    IStETHWithdrawal public immutable withdrawal;

    constructor(address _steth, address _weth, address _stEthWithdrawal) {
        steth = IERC20(_steth);
        weth = IWETH(_weth);
        withdrawal = IStETHWithdrawal(_stEthWithdrawal);
    }

    /**
     * @notice Approve the stETH withdrawal contract. Used for redemption requests.
     */
    function approveStETH() external onlyOperatorOrOwner {
        steth.approve(address(withdrawal), type(uint256).max);
    }

    /**
     * @notice Mint stETH with ETH
     */
    function depositETHForStETH(uint256 amount) external onlyOperatorOrOwner {
        _depositETHForStETH(amount);
    }

    /**
     * @notice Mint stETH with WETH
     */
    function depositWETHForStETH(uint256 amount) external onlyOperatorOrOwner {
        // Unwrap the WETH then deposit the ETH.
        weth.withdraw(amount);
        _depositETHForStETH(amount);
    }

    /**
     * @notice Mint stETH with ETH.
     * Reference: https://docs.lido.fi/contracts/lido#fallback
     */
    function _depositETHForStETH(uint256 amount) internal {
        require(address(this).balance >= amount, "OSwap: Insufficient ETH balance");
        (bool success,) = address(steth).call{value: amount}(new bytes(0));
        require(success, "OSwap: ETH transfer failed");
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
        requestIds = withdrawal.requestWithdrawals(amounts, address(this));
    }

    /**
     * @notice Claim the ETH owed from the redemption requests.
     * Before calling this method, caller should check on the request NFTs to ensure the withdrawal was processed.
     */
    function claimStETHWithdrawalForETH(uint256[] memory requestIds) external onlyOperatorOrOwner {
        _claimStETHWithdrawalForETH(requestIds);
    }

    /**
     * @notice Claim the ETH owed from the redemption requests and convert it to WETH.
     * Before calling this method, caller should check on the request NFTs to ensure the withdrawal was processed.
     */
    function claimStETHWithdrawalForWETH(uint256[] memory requestIds) external onlyOperatorOrOwner {
        // Claim the NFTs for ETH.
        _claimStETHWithdrawalForETH(requestIds);

        // Wrap all the received ETH to WETH.
        (bool success,) = address(weth).call{value: address(this).balance}(new bytes(0));
        require(success, "OSwap: ETH transfer failed");
    }

    function _claimStETHWithdrawalForETH(uint256[] memory requestIds) internal {
        uint256 lastIndex = withdrawal.getLastCheckpointIndex();
        uint256[] memory hintIds = withdrawal.findCheckpointHints(requestIds, 1, lastIndex);
        withdrawal.claimWithdrawals(requestIds, hintIds);
    }

    // This method is necessary for receiving the ETH claimed as part of the withdrawal.
    receive() external payable {}
}
