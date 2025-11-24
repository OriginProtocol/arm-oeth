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
    Proxy internal armProxy;
    Proxy internal morphoMarketProxy;
    EthenaARM internal arm;
    MockMorpho internal morpho;
    MorphoMarket internal market;
    EthenaUnstaker[] internal unstakers;
    uint256[] internal unstakerIndices;

    // --- Tokens ---
    IERC20 internal usde;
    IStakedUSDe internal susde;

    // --- Utils ---
    Vm internal vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    //////////////////////////////////////////////////////
    /// --- USERS
    //////////////////////////////////////////////////////
    // --- Users with roles ---
    address internal deployer;
    address internal governor;
    address internal operator;
    address internal treasury;

    // --- Regular users ---
    address internal alice;
    address internal bobby;
    address internal carol;
    address internal david;
    address internal elise;
    address internal frank;
    address internal grace;
    address internal harry;
    address internal dead;

    // --- Group of users ---
    address[] internal makers;
    address[] internal traders;
    mapping(address => uint256[]) internal pendingRequests;

    //////////////////////////////////////////////////////
    /// --- DEFAULT VALUES
    //////////////////////////////////////////////////////
    uint256 internal constant MAKERS_COUNT = 3;
    uint256 internal constant TRADERS_COUNT = 3;
    uint256 internal constant UNSTAKERS_COUNT = 42;
    uint256 internal constant DEFAULT_CLAIM_DELAY = 10 minutes;
    uint256 internal constant DEFAULT_MIN_TOTAL_SUPPLY = 1e12;
    uint256 internal constant DEFAULT_ALLOCATE_THRESHOLD = 1e18;
    uint256 internal constant DEFAULT_MIN_SHARES_TO_REDEEM = 1e7;

    /// @notice Indicates if labels have been set in the Vm.
    function isLabelAvailable() external view virtual returns (bool);
    function isAssumeAvailable() external view virtual returns (bool);
    function isConsoleAvailable() external view virtual returns (bool);

    //////////////////////////////////////////////////////
    /// --- GHOST VALUES
    //////////////////////////////////////////////////////
    // --- USDe values ---
    uint256 internal sumUSDeSwapIn;
    uint256 internal sumUSDeSwapOut;
    uint256 internal sumUSDeUserDeposit;
    uint256 internal sumUSDeUserRedeem;
    uint256 internal sumUSDeUserRequest;
    uint256 internal sumUSDeBaseRedeem;
    uint256 internal sumUSDeFeesCollected;
    uint256 internal sumUSDeMarketDeposit;
    uint256 internal sumUSDeMarketWithdraw;
    mapping(address => uint256) internal mintedUSDe;
    // --- sUSDe values ---
    uint256 internal sumSUSDeSwapIn;
    uint256 internal sumSUSDeSwapOut;
    uint256 internal sumSUSDeBaseRedeem;
}

