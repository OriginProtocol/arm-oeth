// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "test/Base.sol";
import {Helpers} from "test/fork/Harvester/shared/Helpers.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {Harvester} from "contracts/Harvester.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {SiloMarket} from "contracts/markets/SiloMarket.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

import {Sonic} from "contracts/utils/Addresses.sol";

abstract contract Fork_Shared_Test is Base_Test_, Helpers {
    address public oracle;

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
        require(vm.envExists("SONIC_URL"), "SONIC_URL not set");

        // Create and select a fork.
        if (vm.envExists("FORK_BLOCK_NUMBER_SONIC")) {
            vm.createSelectFork("sonic", vm.envUint("FORK_BLOCK_NUMBER_SONIC"));
        } else {
            vm.createSelectFork("sonic");
        }
    }

    function _deployMockContracts() internal {
        os = IERC20(resolver.resolve("OS"));
        ws = IERC20(resolver.resolve("WS"));
    }

    function _generateAddresses() internal {
        // Users and multisigs
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        deployer = makeAddr("deployer");
        feeCollector = makeAddr("fee collector");
        oracle = makeAddr("MOCK ORACLE");
        originARM = OriginARM(makeAddr("OriginARM"));
        operator = makeAddr("OPERATOR");
        governor = makeAddr("GOVERNOR");
    }

    function _deployContracts() internal {
        vm.startPrank(deployer);

        // --- Deploy Proxy
        harvesterProxy = new Proxy();
        vm.label(address(harvesterProxy), "HARVESTER PROXY");
        Proxy siloMarketProxy = new Proxy();
        vm.label(address(siloMarketProxy), "SILO MARKET PROXY");

        // --- Deploy OriginARM implementation
        harvester = new Harvester(address(ws), Sonic.MAGPIE_ROUTER);
        siloMarket = new SiloMarket(address(originARM), Sonic.SILO_VARLAMORE_S_VAULT, Sonic.SILO_VARLAMORE_S_GAUGE);

        // --- Initialize the proxy
        harvesterProxy.initialize(
            address(harvester), governor, abi.encodeWithSelector(Harvester.initialize.selector, oracle, 1000, operator)
        );

        siloMarketProxy.initialize(
            address(siloMarket),
            governor,
            abi.encodeWithSelector(SiloMarket.initialize.selector, address(harvesterProxy))
        );

        harvester = Harvester(address(harvesterProxy));
        siloMarket = SiloMarket(address(siloMarketProxy));

        vm.stopPrank();
    }
}
