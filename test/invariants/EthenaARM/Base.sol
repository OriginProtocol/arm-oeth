// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {MockMorpho} from "test/invariants/EthenaARM/mocks/MockMorpho.sol";
import {MorphoMarket} from "src/contracts/markets/MorphoMarket.sol";
import {EthenaUnstaker} from "contracts/EthenaUnstaker.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IStakedUSDe} from "contracts/Interfaces.sol";

// Tests
import {Vm} from "./helpers/Vm.sol";

/// @notice This contract should be the common parent for all test contracts.
///         It should be used to define common variables and that will be
///         used across all test contracts. This pattern is used to allow different
///         test contracts to share common variables, and ensure a consistent setup.
/// @dev This contract should be inherited by "Shared" contracts.
/// @dev This contract should only be used as storage for common variables.
/// @dev Helpers and other functions should be defined in a separate contract.
abstract contract Base_Test_ {
    //////////////////////////////////////////////////////
    /// --- CONTRACTS
    //////////////////////////////////////////////////////
    // --- Main contracts ---
    Proxy public armProxy;
    Proxy public morphoMarketProxy;
    EthenaARM public arm;
    MockMorpho public morpho;
    MorphoMarket public market;
    EthenaUnstaker[] public unstakers;
    uint256[] public unstakerIndices;

    // --- Tokens ---
    IERC20 public usde;
    IStakedUSDe public susde;

    // --- Utils ---
    Vm public vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    //////////////////////////////////////////////////////
    /// --- USERS
    //////////////////////////////////////////////////////
    // --- Users with roles ---
    address public deployer;
    address public governor;
    address public operator;
    address public treasury;

    // --- Regular users ---
    address public alice;
    address public bobby;
    address public carol;
    address public david;
    address public elise;
    address public frank;
    address public grace;
    address public harry;
    address public dead;

    // --- Group of users ---
    address[] public makers;
    address[] public traders;
    mapping(address => uint256[]) public pendingRequests;

    //////////////////////////////////////////////////////
    /// --- DEFAULT VALUES
    //////////////////////////////////////////////////////
    uint256 public constant MAKERS_COUNT = 3;
    uint256 public constant TRADERS_COUNT = 3;
    uint256 public constant UNSTAKERS_COUNT = 42;
    uint256 public constant DEFAULT_CLAIM_DELAY = 10 minutes;
    uint256 public constant DEFAULT_MIN_TOTAL_SUPPLY = 1e12;
    uint256 public constant DEFAULT_ALLOCATE_THRESHOLD = 1e18;
    uint256 public constant DEFAULT_MIN_SHARES_TO_REDEEM = 1e7;

    /// @notice Indicates if labels have been set in the Vm.
    function isLabelAvailable() external view virtual returns (bool);
    function isAssumeAvailable() external view virtual returns (bool);
    function isConsoleAvailable() external view virtual returns (bool);

    //////////////////////////////////////////////////////
    /// --- GHOST VALUES
    //////////////////////////////////////////////////////
    // --- USDe values ---
    uint256 public sumUSDeSwapIn;
    uint256 public sumUSDeSwapOut;
    uint256 public sumUSDeUserDeposit;
    uint256 public sumUSDeUserRedeem;
    uint256 public sumUSDeBaseRedeem;
    uint256 public sumUSDeFeesCollected;
    uint256 public sumUSDeMarketDeposit;
    uint256 public sumUSDeMarketWithdraw;
    // --- sUSDe values ---
    uint256 public sumSUSDeSwapIn;
    uint256 public sumSUSDeSwapOut;
    uint256 public sumSUSDeBaseRedeem;
}

