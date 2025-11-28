// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "test/Base.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {EthenaUnstaker} from "contracts/EthenaUnstaker.sol";

// Interfaces
import {Mainnet} from "src/contracts/utils/Addresses.sol";
import {IERC20, IERC4626, IStakedUSDe} from "contracts/Interfaces.sol";

abstract contract Fork_Shared_Test is Base_Test_ {
    uint256 public constant MAX_UNSTAKERS = 42;

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

        // Ignite test contract
        _ignite();

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
        usde = IERC20(Mainnet.USDE);
        susde = IERC4626(Mainnet.SUSDE);
        badToken = IERC20(address(0xDEADBEEF));
    }

    function _generateAddresses() internal {
        // Generate addresses
        governor = makeAddr("governor");
        deployer = makeAddr("deployer");
        operator = makeAddr("operator");
        feeCollector = makeAddr("feeCollector");
    }

    function _deployContracts() internal {
        vm.startPrank(deployer);
        // 1. Deploy Ethena ARM
        ethenaARM = new EthenaARM({
            _usde: address(usde),
            _susde: address(susde),
            _claimDelay: 10 minutes,
            _minSharesToRedeem: 1e7,
            _allocateThreshold: 1 ether
        });

        // 2. Deploy Ethena ARM Proxy
        ethenaProxy = new Proxy();

        // Fund deployer with USDe and approve proxy to pull USDe for initialization
        deal(address(usde), deployer, 1e12);
        usde.approve(address(ethenaProxy), 1e12);

        // 3. Initialize Ethena ARM Proxy
        bytes memory data = abi.encodeWithSelector(
            EthenaARM.initialize.selector,
            "Ethena Staked USDe ARM",
            "ARM-sUSDe-USDe",
            operator, // operator
            2000, // 20% fee
            feeCollector, // feeCollector
            address(0) // capManager
        );

        ethenaProxy.initialize(address(ethenaARM), governor, data);
        vm.stopPrank();

        // Assign Ethena ARM instance
        ethenaARM = EthenaARM(address(ethenaProxy));
    }

    function _ignite() internal virtual {
        // Assign contract instances
        deal(address(usde), address(this), 1_000_000 ether);
        deal(address(susde), address(this), 1_000_000 ether);

        // Approve USDe and SUSDe to Ethena ARM
        usde.approve(address(ethenaARM), type(uint256).max);
        susde.approve(address(ethenaARM), type(uint256).max);

        // Deposit some usde in the ARM
        ethenaARM.deposit(10_000 ether);

        // Swap usde to susde using ARM to have some susde balance
        ethenaARM.swapExactTokensForTokens(IERC20(address(susde)), usde, 5_000 ether, 0, address(this));

        vm.startPrank(ethenaARM.owner());
        ethenaARM.setUnstakers(_deployUnstakers());
        vm.stopPrank();
    }

    function _deployUnstakers() internal returns (address[MAX_UNSTAKERS] memory unstakers) {
        for (uint256 i; i < MAX_UNSTAKERS; i++) {
            address unstaker = address(new EthenaUnstaker(payable(ethenaProxy), IStakedUSDe(Mainnet.SUSDE)));
            unstakers[i] = address(unstaker);
        }
    }
}
