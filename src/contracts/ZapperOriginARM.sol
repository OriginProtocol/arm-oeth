// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

// Contracts
import {Ownable} from "./Ownable.sol";

// Interfaces
import {IWETH} from "./Interfaces.sol";
import {IERC20} from "./Interfaces.sol";
import {ILiquidityProviderARM} from "./Interfaces.sol";

/**
 * @title Zapper contract for the Origin (OS) Automated Redemption Manager (ARM)
 * Converts S to wS and deposits it to the Origin ARM to receive ARM LP shares.
 * @author Origin Protocol Inc
 */
contract ZapperOriginARM is Ownable {
    IWETH public immutable ws;
    /// @notice The address of the Lido ARM contract
    ILiquidityProviderARM public immutable arm;

    event Zap(address indexed sender, uint256 assets, uint256 shares);

    constructor(address _ws, address _arm) {
        ws = IWETH(_ws);
        arm = ILiquidityProviderARM(_arm);

        ws.approve(_arm, type(uint256).max);
    }

    /// @notice Deposit ETH to LidoARM and receive ARM LP shares
    receive() external payable {
        deposit();
    }

    /// @notice Deposit S to OriginARM and receive ARM shares
    /// @return shares The amount of ARM LP shares sent to the depositor
    function deposit() public payable returns (uint256 shares) {
        // Wrap all S to wS
        uint256 sBalance = address(this).balance;
        ws.deposit{value: sBalance}();

        // Deposit all wS to the ARM
        shares = arm.deposit(sBalance, msg.sender);

        // Emit event
        emit Zap(msg.sender, sBalance, shares);
    }

    /// @notice Rescue ERC20 tokens
    /// @param token The address of the ERC20 token
    function rescueERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }
}
