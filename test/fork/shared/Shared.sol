// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Modifiers} from "test/fork/utils/Modifiers.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OEthARM} from "contracts/OethARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IOETHVault} from "contracts/Interfaces.sol";

// Utils
import {Mainnet} from "test/utils/Addresses.sol";

/// @notice This contract should inherit (directly or indirectly) from `Base_Test_`.
///         It should be used to setup the FORK test ONLY!
/// @dev This contract will be used to:
///         - Create and select a fork.
///         - Create users (generating addresses).
///         - Deploy contracts in the fork for testing.
///         - Label contracts for easy identification.
///         - Apply post deployment setup if needed.
/// @dev This contract can inherit from other `Helpers` contracts to add more functionality like:
///         - Modifiers used often in tests.
///         - Extra assertions (like to compare unusual types).
///         - Maths helpers.
///         - etc.
/// @dev This contract should be inherited by `Concrete` and `Fuzz` test contracts.
/// @dev `setUp()` function should be marked as `virtual` to allow overriding in child contracts.
abstract contract Fork_Shared_Test_ is Modifiers {
    uint256 public forkId;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();

        // 1. Create fork.
        _createAndSelectFork();

        // 2. Create users.
        _generateAddresses();

        // 3. Deploy contracts.
        _deployContracts();

        // 4. Label contracts.
        _label();
    }

    //////////////////////////////////////////////////////
    /// --- HELPERS
    //////////////////////////////////////////////////////
    function _createAndSelectFork() internal {
        // Check if the PROVIDER_URL is set.
        require(vm.envExists("PROVIDER_URL"), "PROVIDER_URL not set");

        // Create and select a fork.
        forkId = vm.createSelectFork(vm.envString("PROVIDER_URL"));
    }

    function _generateAddresses() internal {
        // Users.
        alice = makeAddr("alice");
        deployer = makeAddr("deployer");
        operator = Mainnet.STRATEGIST;

        // Contracts.
        oeth = IERC20(Mainnet.OETH);
        weth = IERC20(Mainnet.WETH);
        vault = IOETHVault(Mainnet.OETHVAULT);
    }

    function _deployContracts() internal {
        // Deploy Proxy.
        proxy = new Proxy();

        // Deploy OEthARM implementation.
        address implementation = address(new OEthARM());
        vm.label(implementation, "OETH ARM IMPLEMENTATION");

        // Initialize Proxy with OEthARM implementation.
        proxy.initialize(implementation, Mainnet.TIMELOCK, "");

        // Set the Proxy as the OEthARM.
        oethARM = OEthARM(address(proxy));
    }

    function _label() internal {
        vm.label(address(oeth), "OETH");
        vm.label(address(weth), "WETH");
        vm.label(address(vault), "OETH VAULT");
        vm.label(address(oethARM), "OETH ARM");
        vm.label(address(proxy), "OETH ARM PROXY");
        vm.label(Mainnet.STRATEGIST, "STRATEGIST");
        vm.label(Mainnet.WHALE_OETH, "WHALE OETH");
        vm.label(Mainnet.TIMELOCK, "TIMELOCK");
        vm.label(Mainnet.NULL, "NULL");
    }
}
