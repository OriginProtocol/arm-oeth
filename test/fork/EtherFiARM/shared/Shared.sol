// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "test/Base.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";
import {EtherFiAssetAdapter} from "contracts/adapters/EtherFiAssetAdapter.sol";
import {WeETHAssetAdapter} from "contracts/adapters/WeETHAssetAdapter.sol";

// Interfaces
import {Mainnet} from "src/contracts/utils/Addresses.sol";
import {IERC20, IEETHWithdrawalNFT} from "contracts/Interfaces.sol";

abstract contract Fork_Shared_Test is Base_Test_ {
    IEETHWithdrawalNFT public etherfiWithdrawalNFT;
    WeETHAssetAdapter public weethAssetAdapter;

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
        // Check if the MAINNET_URL is set.
        require(vm.envExists("MAINNET_URL"), "MAINNET_URL not set");

        // Create and select a fork.
        if (vm.envExists("FORK_BLOCK_NUMBER_MAINNET")) {
            vm.createSelectFork("mainnet", vm.envUint("FORK_BLOCK_NUMBER_MAINNET"));
        } else {
            vm.createSelectFork("mainnet");
        }
    }

    function _deployMockContracts() internal {
        eeth = IERC20(Mainnet.EETH);
        weth = IERC20(Mainnet.WETH);
        weeth = IERC20(Mainnet.WEETH);
        etherfiWithdrawalNFT = IEETHWithdrawalNFT(Mainnet.ETHERFI_WITHDRAWAL_NFT);
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
        EtherFiARM etherfiImpl = new EtherFiARM(address(eeth), address(weth), 10 minutes, 0, 0);

        // Deployer will need WETH to initialize the ARM.
        deal(address(weth), deployer, 1e15);
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

        etherfiAssetAdapter = new EtherFiAssetAdapter(
            address(etherfiARM),
            address(eeth),
            address(weth),
            Mainnet.ETHERFI_WITHDRAWAL,
            Mainnet.ETHERFI_WITHDRAWAL_NFT
        );
        etherfiAssetAdapter.initialize();
        etherfiARM.addBaseAsset(
            address(eeth),
            address(etherfiAssetAdapter),
            0.9997e36,
            1e36,
            type(uint128).max,
            type(uint128).max,
            0.9998e36,
            true
        );

        weethAssetAdapter = new WeETHAssetAdapter(
            address(etherfiARM),
            address(weeth),
            address(eeth),
            address(weth),
            Mainnet.ETHERFI_WITHDRAWAL,
            Mainnet.ETHERFI_WITHDRAWAL_NFT
        );
        weethAssetAdapter.initialize();
        etherfiARM.addBaseAsset(
            address(weeth),
            address(weethAssetAdapter),
            0.9997e36,
            1e36,
            type(uint128).max,
            type(uint128).max,
            0.9998e36,
            false
        );
    }
}
