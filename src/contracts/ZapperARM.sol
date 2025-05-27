// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

// Contracts
import {Ownable} from "./Ownable.sol";

// Interfaces
import {IWETH} from "./Interfaces.sol";
import {IERC20} from "./Interfaces.sol";
import {ILiquidityProviderARM} from "./Interfaces.sol";

/**
 * @title Zapper contract for Automated Redemption Managers (ARMs)
 * Converts S to wS and deposits it to an ARM to receive ARM LP shares.
 * @author Origin Protocol Inc
 */
contract ZapperARM is Ownable {
    IWETH public immutable ws;

    event Zap(address indexed arm, address indexed sender, uint256 assets, uint256 shares);

    constructor(address _ws) {
        ws = IWETH(_ws);
    }

    /// @notice Deposit S to OriginARM and receive ARM shares
    /// @param arm The address of the ARM contract to deposit to
    /// @return shares The amount of ARM LP shares sent to the depositor
    function deposit(address arm) public payable returns (uint256 shares) {
        // Wrap all S to wS
        uint256 sBalance = address(this).balance;
        ws.deposit{value: sBalance}();

        // Deposit all wS to the ARM
        ws.approve(arm, sBalance);
        shares = ILiquidityProviderARM(arm).deposit(sBalance, msg.sender);

        // Emit event
        emit Zap(arm, msg.sender, sBalance, shares);
    }

    /// @notice Rescue ERC20 tokens
    /// @param token The address of the ERC20 token
    /// @param amount The amount of tokens to rescue
    function rescueERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }
}
