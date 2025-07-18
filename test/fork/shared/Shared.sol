// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Deployer
import {DeployManager} from "script/deploy/DeployManager.sol";

// Test imports
import {Modifiers} from "test/fork/utils/Modifiers.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OethARM} from "contracts/OethARM.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {ZapperLidoARM} from "contracts/ZapperLidoARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IOriginVault} from "contracts/Interfaces.sol";

// Utils
import {Mainnet} from "contracts/utils/Addresses.sol";
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
        if (vm.envExists("FORK_BLOCK_NUMBER_MAINNET")) {
            forkId = vm.createSelectFork("mainnet", vm.envUint("FORK_BLOCK_NUMBER_MAINNET"));
        } else {
            forkId = vm.createSelectFork("mainnet");
        }
    }

    function _generateAddresses() internal {
        // Users and multisigs
        alice = makeAddr("alice");
        deployer = makeAddr("deployer");
        feeCollector = makeAddr("fee collector");

        operator = resolver.resolve("OPERATOR");
        governor = resolver.resolve("GOVERNOR");
        oethWhale = resolver.resolve("WHALE_OETH");

        // Contracts.
        oeth = IERC20(resolver.resolve("OETH"));
        weth = IERC20(resolver.resolve("WETH"));
        steth = IERC20(resolver.resolve("STETH"));
        wsteth = IERC20(resolver.resolve("WSTETH"));
        vault = IOriginVault(resolver.resolve("OETH_VAULT"));
        badToken = IERC20(vm.randomAddress());
    }

    function _deployContracts() internal {
        // --- Deploy all proxies ---
        proxy = new Proxy();
        lpcProxy = new Proxy();
        lidoProxy = new Proxy();

        // --- Deploy OethARM implementation ---
        // Deploy OethARM implementation.
        address implementation = address(new OethARM(address(oeth), address(weth), address(vault)));
        vm.label(implementation, "OETH ARM IMPLEMENTATION");

        // Initialize Proxy with OethARM implementation.
        bytes memory data = abi.encodeWithSignature("initialize(address)", operator);
        proxy.initialize(implementation, governor, data);

        // Set the Proxy as the OethARM.
        oethARM = OethARM(address(proxy));

        // --- Deploy CapManager implementation ---
        // Deploy CapManager implementation.
        CapManager capManagerImpl = new CapManager(address(lidoProxy));

        // Initialize Proxy with CapManager implementation.
        lpcProxy.initialize(address(capManagerImpl), address(this), data);

        // Set the Proxy as the CapManager.
        capManager = CapManager(payable(address(lpcProxy)));

        capManager.setTotalAssetsCap(100 ether);

        address[] memory liquidityProviders = new address[](1);
        liquidityProviders[0] = address(this);
        capManager.setLiquidityProviderCaps(liquidityProviders, 20 ether);
        capManager.setTotalAssetsCap(100 ether);

        // --- Deploy LidoARM implementation ---
        // Deploy LidoARM implementation.
        LidoARM lidoImpl = new LidoARM(address(steth), address(weth), Mainnet.LIDO_WITHDRAWAL, 10 minutes);

        // Deployer will need WETH to initialize the ARM.
        deal(address(weth), address(this), 1e12);
        weth.approve(address(lidoProxy), type(uint256).max);
        steth.approve(address(lidoProxy), type(uint256).max);

        // Initialize Proxy with LidoARM implementation.
        data = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address,address)",
            "Lido ARM",
            "ARM-ST",
            operator,
            2000, // 20% performance fee
            feeCollector,
            address(lpcProxy)
        );
        lidoProxy.initialize(address(lidoImpl), address(this), data);

        // Set the Proxy as the LidoARM.
        lidoARM = LidoARM(payable(address(lidoProxy)));

        // set prices
        lidoARM.setPrices(992 * 1e33, 1001 * 1e33);

        // --- Deploy ZapperLidoARM ---
        zapperLidoARM = new ZapperLidoARM(address(weth), address(lidoProxy));
    }

    function _label() internal {
        vm.label(address(oeth), "OETH");
        vm.label(address(weth), "WETH");
        vm.label(address(steth), "stETH");
        vm.label(address(badToken), "BAD TOKEN");
        vm.label(address(vault), "OETH VAULT");
        vm.label(address(oethARM), "OETH ARM");
        vm.label(address(proxy), "OETH ARM PROXY");
        vm.label(address(lidoARM), "LIDO ARM");
        vm.label(address(lidoProxy), "LIDO ARM PROXY");
        vm.label(address(capManager), "LIQUIDITY PROVIDER CONTROLLER");
        vm.label(address(zapperLidoARM), "ZAPPER LIDO ARM");
        vm.label(operator, "OPERATOR");
        vm.label(oethWhale, "WHALE OETH");
        vm.label(governor, "GOVERNOR");
        vm.label(address(0), "ZERO");
    }
}
