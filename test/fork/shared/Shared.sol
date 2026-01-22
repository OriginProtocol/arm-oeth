// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Modifiers} from "test/fork/utils/Modifiers.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {ZapperLidoARM} from "contracts/ZapperLidoARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IOriginVault} from "contracts/Interfaces.sol";

// Utils
import {Mainnet} from "contracts/utils/Addresses.sol";

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
    function _createDeployManager() internal {}

    function _createAndSelectFork() internal {
        // Check if the MAINNET_URL is set.
        require(vm.envExists("MAINNET_URL"), "MAINNET_URL not set");

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

        operator = Mainnet.ARM_RELAYER;
        governor = Mainnet.GOVERNOR_FIVE;
        oethWhale = Mainnet.WOETH;

        // Contracts.
        oeth = IERC20(Mainnet.OETH);
        weth = IERC20(Mainnet.WETH);
        steth = IERC20(Mainnet.STETH);
        wsteth = IERC20(Mainnet.WSTETH);
        vault = IOriginVault(Mainnet.OETH_VAULT);
        badToken = IERC20(vm.randomAddress());
    }

    function _deployContracts() internal {
        // --- Deploy all proxies ---
        lpcProxy = new Proxy();
        lidoProxy = new Proxy();
        // --- Deploy CapManager implementation ---
        // Deploy CapManager implementation.
        CapManager capManagerImpl = new CapManager(address(lidoProxy));

        // Initialize Proxy with CapManager implementation.
        bytes memory data = abi.encodeWithSignature("initialize(address)", operator);
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
        LidoARM lidoImpl = new LidoARM(address(steth), address(weth), Mainnet.LIDO_WITHDRAWAL, 10 minutes, 0, 0);

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
