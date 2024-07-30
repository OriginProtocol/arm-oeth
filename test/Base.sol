// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Test} from "forge-std/Test.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OEthARM} from "contracts/OethARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IOETHVault} from "contracts/Interfaces.sol";

/// @notice This contract should be the common parent for all test contracts.
///         It should be used to define common variables and that will be
///         used across all test contracts. This pattern is used to allow different
///         test contracts to share common variables, and ensure a consistent setup.
/// @dev This contract should be inherited by "Shared" contracts.
/// @dev This contract should only be used as storage for common variables.
/// @dev Helpers and other functions should be defined in a separate contract.
abstract contract Base_Test_ is Test {
    //////////////////////////////////////////////////////
    /// --- CONTRACTS
    //////////////////////////////////////////////////////
    Proxy public proxy;
    OEthARM public oethARM;

    //////////////////////////////////////////////////////
    /// --- INTERFACES
    //////////////////////////////////////////////////////
    IERC20 public oeth;
    IERC20 public weth;
    IOETHVault public vault;

    //////////////////////////////////////////////////////
    /// --- EOA
    //////////////////////////////////////////////////////
    address public alice;
    address public deployer;
    address public operator;
    address public multisig;
    address public strategist;

    //////////////////////////////////////////////////////
    /// --- DEFAULT VALUES
    //////////////////////////////////////////////////////
    uint256 public constant DEFAULT_AMOUNT = 1 ether;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual {}
}
