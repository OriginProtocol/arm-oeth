// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Contracts
import {Ownable} from "./Ownable.sol";

// Interfaces
import {IWETH} from "./Interfaces.sol";
import {IERC20} from "./Interfaces.sol";
import {ILiquidityProviderARM} from "./Interfaces.sol";

/**
 * @title Zapper contract for the Lido (stETH) Automated Redemption Manager (ARM)
 * Converts ETH to WETH and deposits it to the Lido ARM to receive ARM LP shares.
 * @author Origin Protocol Inc
 */
contract ZapperLidoARM is Ownable {
    IWETH public immutable weth;
    /// @notice The address of the Lido ARM contract
    ILiquidityProviderARM public immutable lidoArm;

    event Zap(address indexed sender, uint256 assets, uint256 shares);

    constructor(address _weth, address _lidoArm) {
        weth = IWETH(_weth);
        lidoArm = ILiquidityProviderARM(_lidoArm);

        weth.approve(_lidoArm, type(uint256).max);
    }

    /// @notice Deposit ETH to LidoARM and receive ARM LP shares
    receive() external payable {
        deposit();
    }

    /// @notice Deposit ETH to LidoARM and receive shares
    /// @return shares The amount of ARM LP shares sent to the depositor
    function deposit() public payable returns (uint256 shares) {
        // Wrap all ETH to WETH
        uint256 ethBalance = address(this).balance;
        weth.deposit{value: ethBalance}();

        // Deposit all WETH to LidoARM
        shares = lidoArm.deposit(ethBalance, msg.sender);

        // Emit event
        emit Zap(msg.sender, ethBalance, shares);
    }

    /// @notice Rescue ERC20 tokens
    /// @param token The address of the ERC20 token
    function rescueERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }
}
