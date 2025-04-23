// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "test/Base.sol";
import {Modifiers} from "test/fork/OriginARM/shared/Modifiers.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OriginARM} from "contracts/OriginARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SiloMarket} from "contracts/markets/SiloMarket.sol";
import {IOriginVault} from "contracts/Interfaces.sol";

// Mocks
import {MockVault} from "test/unit/mocks/MockVault.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

abstract contract Fork_Shared_Test is Base_Test_, Modifiers {
    uint256 public constant CLAIM_DELAY = 1 days;
    uint256 public constant DEFAULT_FEE = 1000; // 10%

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
        os = IERC20(address(new MockERC20("Origin Sonic", "OS", 18)));
        ws = IERC20(resolver.resolve("WS"));
        vault = IOriginVault(address(new MockVault(IERC20(os))));
        market = IERC4626(resolver.resolve("SILO_WOS_S_MARKET"));
        vm.label(address(market), "SILO_WOS_S_MARKET");
    }

    function _generateAddresses() internal {
        // Users and multisigs
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        deployer = makeAddr("deployer");
        feeCollector = makeAddr("fee collector");

        operator = makeAddr("OPERATOR");
        governor = makeAddr("GOVERNOR");
    }

    function _deployContracts() internal {
        vm.startPrank(deployer);

        // --- Deploy Proxy
        originARMProxy = new Proxy();
        Proxy marketAdapterProxy = new Proxy();

        // --- Deploy OriginARM implementation
        originARM = new OriginARM(address(os), address(ws), address(vault), CLAIM_DELAY);

        // --- Deploy SiloMarket implementation
        siloMarket = new SiloMarket(address(originARMProxy), address(market));

        // Initialization requires 1e12 liquid assets to mint to dead address.
        // Deployer approve the proxy to transfer 1e12 liquid assets.
        ws.approve(address(originARMProxy), 1e12);
        // Mint 1e12 liquid assets to the deployer.
        deal(address(ws), deployer, 1e12);

        // --- Initialize the proxy
        originARMProxy.initialize(
            address(originARM),
            governor,
            abi.encodeWithSelector(
                OriginARM.initialize.selector, "Origin ARM", "OARM", governor, DEFAULT_FEE, feeCollector, address(0)
            )
        );

        // --- Initialize the SiloMarket proxy
        marketAdapterProxy.initialize(
            address(siloMarket), governor, abi.encodeWithSelector(SiloMarket.initialize.selector, operator)
        );

        vm.stopPrank();

        // --- Set the proxy as the OriginARM
        originARM = OriginARM(address(originARMProxy));

        // --- Set the SiloMarket as the market
        siloMarket = SiloMarket(address(marketAdapterProxy));

        // set prices
        vm.prank(governor);
        originARM.setPrices(992 * 1e33, 1001 * 1e33);
    }
}
