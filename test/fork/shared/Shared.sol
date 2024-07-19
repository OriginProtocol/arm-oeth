// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Base_Test_} from "../../Base.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OEthARM} from "contracts/OethARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IOETHVault} from "contracts/Interfaces.sol";

// Utils
import {Mainnet} from "test/utils/Addresses.sol";

abstract contract Fork_Shared_Test_ is Base_Test_ {
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

    /// @notice Override `deal()` function to handle OETH special case.
    function deal(address token, address to, uint256 amount) internal override {
        // Handle OETH special case, as rebasing tokens are not supported by the VM.
        if (token == address(oeth)) {
            // Check than whale as enough OETH.
            require(oeth.balanceOf(Mainnet.WHALE_OETH) >= amount, "Fork_Shared_Test_: Not enough OETH in WHALE_OETH");

            // Transfer OETH from WHALE_OETH to the user.
            vm.prank(Mainnet.WHALE_OETH);
            oeth.transfer(to, amount);
        } else {
            super.deal(token, to, amount);
        }
    }
}
