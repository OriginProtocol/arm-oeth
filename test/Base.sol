// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Test} from "forge-std/Test.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OethARM} from "contracts/OethARM.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {Harvester} from "contracts/Harvester.sol";
import {CapManager} from "contracts/CapManager.sol";
import {SiloMarket} from "contracts/markets/SiloMarket.sol";
import {ZapperLidoARM} from "contracts/ZapperLidoARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IOriginVault} from "contracts/Interfaces.sol";

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
    Proxy public originARMProxy;
    Proxy public harvesterProxy;
    OethARM public oethARM;
    LidoARM public lidoARM;
    Harvester public harvester;
    OriginARM public originARM;
    CapManager public capManager;
    SiloMarket public siloMarket;
    ZapperLidoARM public zapperLidoARM;

    IERC20 public ws;
    IERC20 public os;
    IERC20 public wos;
    IERC20 public oeth;
    IERC20 public weth;
    IERC20 public steth;
    IERC20 public wsteth;
    IERC20 public badToken;
    IERC4626 public market;
    IERC4626 public market2;
    IOriginVault public vault;

    //////////////////////////////////////////////////////
    /// --- Governance, multisigs and EOAs
    //////////////////////////////////////////////////////
    address public alice;
    address public bob;
    address public charlie;
    address public dave;
    address public eve;
    address public frank;
    address public george;
    address public harry;

    address public deployer;
    address public governor;
    address public operator;
    address public oethWhale;
    address public feeCollector;
    address public lidoWithdraw;

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

    /// @notice Better if called once all contract have been depoyed.
    function labelAll() public virtual {
        // Contracts
        _labelNotNull(address(proxy), "DEFAULT PROXY");
        _labelNotNull(address(lpcProxy), "LPC PROXY");
        _labelNotNull(address(lidoProxy), "LIDO ARM PROXY");
        _labelNotNull(address(oethARM), "OETH ARM");
        _labelNotNull(address(lidoARM), "LIDO ARM");
        _labelNotNull(address(originARM), "ORIGIN ARM");
        _labelNotNull(address(capManager), "CAP MANAGER");
        _labelNotNull(address(siloMarket), "SILO MARKET ADAPTER");

        _labelNotNull(address(ws), "WS");
        _labelNotNull(address(os), "OS");
        _labelNotNull(address(oeth), "OETH");
        _labelNotNull(address(weth), "WETH");
        _labelNotNull(address(steth), "STETH");
        _labelNotNull(address(wsteth), " WRAPPED STETH");
        _labelNotNull(address(badToken), "BAD TOKEN");
        _labelNotNull(address(vault), "OETH VAULT");

        // Governance, multisig and EOAs
        _labelNotNull(alice, "Alice");
        _labelNotNull(bob, "Bob");
        _labelNotNull(charlie, "Charlie");
        _labelNotNull(dave, "Dave");
        _labelNotNull(eve, "Eve");
        _labelNotNull(frank, "Frank");
        _labelNotNull(george, "George");
        _labelNotNull(harry, "Harry");

        _labelNotNull(deployer, "Deployer");
        _labelNotNull(governor, "Governor");
        _labelNotNull(operator, "Operator");
        _labelNotNull(oethWhale, "OETH Whale");
        _labelNotNull(feeCollector, "Fee Collector");
        _labelNotNull(lidoWithdraw, "Lido Withdraw");
    }

    function _labelNotNull(address _address, string memory _name) internal {
        if (_address != address(0)) vm.label(_address, _name);
    }
}
