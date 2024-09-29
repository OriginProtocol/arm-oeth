// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Base_Test_} from "test/Base.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {LiquidityProviderController} from "contracts/LiquidityProviderController.sol";
import {WETH} from "@solmate/tokens/WETH.sol";

// Mocks
import {MockSTETH} from "../mocks/MockSTETH.sol";
import {MockLidoWithdraw} from "../mocks/MockLidoWithdraw.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

abstract contract Invariant_Shared_Test_ is Base_Test_ {
    address[] public users;
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////

    function setUp() public virtual override {
        super.setUp();

        // 1. Setup a realistic test environnement, not needed as not time related.
        // _setUpRealisticEnvironnement()

        // 2. Create user
        _createUsers();

        // To increase performance, we will not use fork., mocking contract instead.
        // 3. Deploy mocks.
        _deployMocks();

        // 4. Deploy contracts.
        _deployContracts();

        // 5. Label addresses
        labelAll();
    }

    function _setUpRealisticEnvironnement() private {
        vm.warp(1000);
        vm.roll(1000);
    }

    function _createUsers() private {
        // Users with role
        deployer = makeAddr("Deployer");
        governor = makeAddr("Governor");
        operator = makeAddr("Operator");
        feeCollector = makeAddr("Fee Collector");

        // Random users
        users.push(alice);
        users.push(bob);
        users.push(charlie);
        users.push(dave);
        users.push(eve);
        users.push(frank);
        users.push(george);
        users.push(harry);
    }

    //////////////////////////////////////////////////////
    /// --- MOCKS
    //////////////////////////////////////////////////////
    function _deployMocks() private {
        // WETH
        weth = IERC20(address(new WETH()));

        // STETH
        steth = IERC20(address(new MockSTETH()));

        // Lido Withdraw
        lidoWithdraw = address(new MockLidoWithdraw(address(steth)));
    }

    //////////////////////////////////////////////////////
    /// --- CONTRACTS
    //////////////////////////////////////////////////////
    function _deployContracts() private {
        vm.startPrank(deployer);

        // 1. Deploy all proxies.
        _deployProxies();

        // 2. Deploy Liquidity Provider Controller.
        _deployLPC();

        // 3. Deploy Lido ARM.
        _deployLidoARM();

        vm.stopPrank();
    }

    function _deployProxies() private {
        lpcProxy = new Proxy();
        lidoProxy = new Proxy();
    }

    function _deployLPC() private {
        // Deploy LiquidityProviderController implementation.
        LiquidityProviderController lpcImpl = new LiquidityProviderController(address(lidoProxy));

        // Initialize Proxy with LiquidityProviderController implementation.
        bytes memory data = abi.encodeWithSignature("initialize(address)", operator);
        lpcProxy.initialize(address(lpcImpl), address(this), data);

        // Set the Proxy as the LiquidityProviderController.
        liquidityProviderController = LiquidityProviderController(payable(address(lpcProxy)));
    }

    function _deployLidoARM() private {
        // Deploy LidoARM implementation.
        LidoARM lidoImpl = new LidoARM(address(steth), address(weth), lidoWithdraw);

        // Deployer will need WETH to initialize the ARM.
        deal(address(weth), address(deployer), MIN_TOTAL_SUPPLY);
        weth.approve(address(lidoProxy), MIN_TOTAL_SUPPLY);

        // Initialize Proxy with LidoARM implementation.
        bytes memory data = abi.encodeWithSignature(
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
    }
}
