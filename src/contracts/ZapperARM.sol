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
 * Converts native currency to wrapped currency, deposits it to an ARM and receives ARM LP shares.
 * @author Origin Protocol Inc
 */
contract ZapperARM is Ownable {
    /// @notice The address of the wrapped token. eg WETH or wS
    IWETH public immutable wrappedCurrency;

    event Zap(address indexed arm, address indexed sender, uint256 assets, uint256 shares);

    constructor(address _wrappedCurrency) {
        wrappedCurrency = IWETH(_wrappedCurrency);
    }

    /// @notice Convert native currency to wrapped currency, deposit it to an ARM and receive ARM shares
    /// @param arm The address of the ARM contract to deposit to
    /// @return shares The amount of ARM LP shares sent to the depositor
    function deposit(address arm) public payable returns (uint256 shares) {
        // Wrap all native currency sent
        uint256 balance = address(this).balance;
        wrappedCurrency.deposit{value: balance}();

        // Deposit all wrapped currency to the ARM
        wrappedCurrency.approve(arm, balance);
        shares = ILiquidityProviderARM(arm).deposit(balance, msg.sender);

        // Emit event
        emit Zap(arm, msg.sender, balance, shares);
    }

    /// @notice Rescue ERC20 tokens
    /// @param token The address of the ERC20 token
    /// @param amount The amount of tokens to rescue
    function rescueERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }
}
