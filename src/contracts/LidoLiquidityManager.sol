// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableOperable} from "./OwnableOperable.sol";
import {IERC20, IWETH, IStETHWithdrawal} from "./Interfaces.sol";

abstract contract LidoLiquidityManager is OwnableOperable {
    IERC20 public immutable steth;
    IWETH public immutable weth;
    IStETHWithdrawal public immutable withdrawalQueue;

    uint256 public outstandingEther;

    uint256[50] private _gap;

    constructor(address _steth, address _weth, address _lidoWithdrawalQueue) {
        steth = IERC20(_steth);
        weth = IWETH(_weth);
        withdrawalQueue = IStETHWithdrawal(_lidoWithdrawalQueue);
    }

    /**
     * @notice Approve the stETH withdrawal contract. Used for redemption requests.
     */
    function approveStETH() external onlyOperatorOrOwner {
        steth.approve(address(withdrawalQueue), type(uint256).max);
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

        // Increase the Ether outstanding from the Lido Withdrawal Queue
        for (uint256 i = 0; i < amounts.length; i++) {
            outstandingEther += amounts[i];
        }
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
        outstandingEther -= etherAfter - etherBefore;

        // Wrap all the received ETH to WETH.
        (bool success,) = address(weth).call{value: etherAfter}(new bytes(0));
        require(success, "OSwap: ETH transfer failed");

        _postClaimHook(etherAfter);
    }

    function _postClaimHook(uint256 assets) internal virtual;

    function _externalWithdrawQueue() internal view virtual returns (uint256 assets) {
        return outstandingEther;
    }

    // This method is necessary for receiving the ETH claimed as part of the withdrawal.
    receive() external payable {}
}
