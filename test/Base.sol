// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Test} from "forge-std/Test.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OethARM} from "contracts/OethARM.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {LiquidityProviderController} from "contracts/LiquidityProviderController.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IOETHVault} from "contracts/Interfaces.sol";

// Utils
import {AddressResolver} from "contracts/utils/Addresses.sol";

/// @notice This contract should be the common parent for all test contracts.
///         It should be used to define common variables and that will be
///         used across all test contracts. This pattern is used to allow different
///         test contracts to share common variables, and ensure a consistent setup.
/// @dev This contract should be inherited by "Shared" contracts.
/// @dev This contract should only be used as storage for common variables.
/// @dev Helpers and other functions should be defined in a separate contract.
abstract contract Base_Test_ is Test {
    AddressResolver public resolver;

    //////////////////////////////////////////////////////
    /// --- CONTRACTS
    //////////////////////////////////////////////////////
    Proxy public proxy;
    Proxy public lpcProxy;
    Proxy public lidoProxy;
    Proxy public lidoOwnerProxy;
    OethARM public oethARM;
    LidoARM public lidoFixedPriceMultiLpARM;
    LiquidityProviderController public liquidityProviderController;

    IERC20 public oeth;
    IERC20 public weth;
    IERC20 public steth;
    IERC20 public wsteth;
    IERC20 public badToken;
    IOETHVault public vault;

    //////////////////////////////////////////////////////
    /// --- Governance, multisigs and EOAs
    //////////////////////////////////////////////////////
    address public alice;
    address public deployer;
    address public governor;
    address public operator;
    address public oethWhale;
    address public feeCollector;

    //////////////////////////////////////////////////////
    /// --- DEFAULT VALUES
    //////////////////////////////////////////////////////
    uint256 public constant DEFAULT_AMOUNT = 1 ether;
    uint256 public constant MIN_TOTAL_SUPPLY = 1e12;
    uint256 public constant STETH_ERROR_ROUNDING = 2;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual {
        resolver = new AddressResolver();
    }
}
