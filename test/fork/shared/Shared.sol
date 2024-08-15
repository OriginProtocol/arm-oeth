// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Deployer
import {DeployManager} from "script/deploy/DeployManager.sol";

// Test imports
import {Modifiers} from "test/fork/utils/Modifiers.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OethARM} from "contracts/OethARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IOETHVault} from "contracts/Interfaces.sol";

// Utils
import {AddressResolver} from "contracts/utils/Addresses.sol";

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
    DeployManager public deployManager;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();

        // 1. Create deploy manager.
        // _createDeployManager();

        // 2. Create fork.
        _createAndSelectFork();

        // 3. Create users.
        _generateAddresses();

        // 4. Deploy contracts.
        _deployContracts();

        // 5. Label contracts.
        _label();
    }

    //////////////////////////////////////////////////////
    /// --- HELPERS
    //////////////////////////////////////////////////////
    function _createDeployManager() internal {
        deployManager = new DeployManager();

        deployManager.setUp();
        deployManager.run();
    }

    function _createAndSelectFork() internal {
        // Check if the PROVIDER_URL is set.
        require(vm.envExists("PROVIDER_URL"), "PROVIDER_URL not set");

        // Create and select a fork.
        forkId = vm.createSelectFork(vm.envString("PROVIDER_URL"));
    }

    function _generateAddresses() internal {
        // Users and multisigs
        alice = makeAddr("alice");
        deployer = makeAddr("deployer");
        operator = resolver.resolve("OPERATOR");
        governor = resolver.resolve("GOVERNOR");
        oethWhale = resolver.resolve("WHALE_OETH");

        // Contracts.
        oeth = IERC20(resolver.resolve("OETH"));
        weth = IERC20(resolver.resolve("WETH"));
        vault = IOETHVault(resolver.resolve("OETH_VAULT"));
    }

    function _deployContracts() internal {
        // Deploy Proxy.
        proxy = new Proxy();

        // Deploy OethARM implementation.
        address implementation = address(new OethARM(address(oeth), address(weth), address(vault)));
        vm.label(implementation, "OETH ARM IMPLEMENTATION");

        // Initialize Proxy with OethARM implementation.
        bytes memory data = abi.encodeWithSignature("initialize(address)", operator);
        proxy.initialize(implementation, governor, data);

        // Set the Proxy as the OethARM.
        oethARM = OethARM(address(proxy));
    }

    function _label() internal {
        vm.label(address(oeth), "OETH");
        vm.label(address(weth), "WETH");
        vm.label(address(vault), "OETH VAULT");
        vm.label(address(oethARM), "OETH ARM");
        vm.label(address(proxy), "OETH ARM PROXY");
        vm.label(operator, "OPERATOR");
        vm.label(oethWhale, "WHALE OETH");
        vm.label(governor, "GOVERNOR");
        vm.label(address(0), "ZERO");
    }
}
