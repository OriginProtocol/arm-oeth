// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Contracts
import {Ownable} from "./Ownable.sol";

// Interfaces
import {IWETH} from "./Interfaces.sol";
import {IERC20} from "./Interfaces.sol";
import {ILidoARM} from "./Interfaces.sol";

contract ZapperLidoARM is Ownable {
    IWETH public immutable weth;
    ILidoARM public immutable lidoArm;

    event Zap(address indexed sender, uint256 shares);

    constructor(address _weth, address _lidoArm) {
        weth = IWETH(_weth);
        lidoArm = ILidoARM(_lidoArm);

        weth.approve(_lidoArm, type(uint256).max);
    }

    /// @notice Deposit ETH to LidoARM and receive shares
    receive() external payable {
        deposit();
    }

    /// @notice Deposit ETH to LidoARM and receive shares
    function deposit() public payable returns (uint256 shares) {
        // Wrap all ETH to WETH
        uint256 balance = address(this).balance;
        weth.deposit{value: balance}();

        // Deposit all WETH to LidoARM
        shares = lidoArm.deposit(balance);

        // Transfer received shares to msg.sender
        lidoArm.transfer(msg.sender, shares);

        // Emit event
        emit Zap(msg.sender, shares);
    }

    /// @notice Rescue ERC20 tokens
    /// @param token The address of the ERC20 token
    function rescueERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }
}
