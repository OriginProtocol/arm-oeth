// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "test/Base.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";

// Interfaces
import {Mainnet} from "src/contracts/utils/Addresses.sol";
import {IERC20, IEETHWithdrawalNFT, IEETHRedemptionManager} from "contracts/Interfaces.sol";

abstract contract Fork_Shared_Test is Base_Test_ {
    IEETHWithdrawalNFT public etherfiWithdrawalNFT;
    IEETHRedemptionManager public etherfiRedemptionManager;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();

        // Generate a fork
        _createAndSelectFork();

        // Deploy Mock contracts
        _deployMockContracts();

        // Generate addresses
        _generateAddresses();

        // Deploy contracts
        _deployContracts();

        // Label contracts
        labelAll();
    }

    function _createAndSelectFork() internal {
        // Check if the PROVIDER_URL is set.
        require(vm.envExists("PROVIDER_URL"), "PROVIDER_URL not set");

        // Create and select a fork.
        if (vm.envExists("FORK_BLOCK_NUMBER_MAINNET")) {
            vm.createSelectFork("mainnet", vm.envUint("FORK_BLOCK_NUMBER_MAINNET"));
        } else {
            vm.createSelectFork("mainnet");
        }
    }

    function _deployMockContracts() internal {
        eeth = IERC20(resolver.resolve("EETH"));
        weth = IERC20(resolver.resolve("WETH"));
        weeth = IERC20(resolver.resolve("WEETH"));
        etherfiWithdrawalNFT = IEETHWithdrawalNFT(Mainnet.ETHERFI_WITHDRAWAL_NFT);
        etherfiRedemptionManager = IEETHRedemptionManager(Mainnet.ETHERFI_REDEMPTION_MANAGER);
    }

    function _generateAddresses() internal {
        // Users and multisigs
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        deployer = makeAddr("DEPLOYER");
        operator = makeAddr("OPERATOR");
        governor = makeAddr("GOVERNOR");
        feeCollector = makeAddr("FEE_COLLECTOR");
    }

    function _deployContracts() internal {
        vm.startPrank(deployer);

        // --- Deploy EtherFiARM Proxy ---
        // Deploy Proxy contract for the EtherFiARM.
        Proxy etherfiProxy = new Proxy();

        // --- Deploy EtherFiARM implementation ---
        // Deploy EtherFiARM implementation.
        EtherFiARM etherfiImpl = new EtherFiARM(
            address(eeth),
            address(weth),
            Mainnet.ETHERFI_WITHDRAWAL,
            10 minutes,
            0,
            0,
            Mainnet.ETHERFI_WITHDRAWAL_NFT,
            Mainnet.ETHERFI_REDEMPTION_MANAGER
        );

        // Deployer will need WETH to initialize the ARM.
        deal(address(weth), deployer, 1e12);
        weth.approve(address(etherfiProxy), type(uint256).max);
        eeth.approve(address(etherfiProxy), type(uint256).max);

        // Initialize Proxy with EtherFiARM implementation.
        bytes memory data = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address,address)",
            "EtherFi ARM",
            "ARM-EETH",
            operator,
            2000, // 20% performance fee
            feeCollector,
            address(lpcProxy)
        );
        etherfiProxy.initialize(address(etherfiImpl), address(this), data);

        // Set the Proxy as the EtherFiARM.
        etherfiARM = EtherFiARM(payable(address(etherfiProxy)));

        vm.stopPrank();
    }
}
