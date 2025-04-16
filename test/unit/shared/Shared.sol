// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "test/Base.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OriginARM} from "contracts/OriginARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IStrategy} from "contracts/Interfaces.sol";
import {IOriginVault} from "contracts/Interfaces.sol";
// Mocks
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockVault} from "test/unit/mocks/MockVault.sol";
import {MockStrategy} from "test/unit/mocks/MockStrategy.sol";

abstract contract Unit_Shared_Test is Base_Test_ {
    uint256 public constant CLAIM_DELAY = 1 days;
    uint256 public constant DEFAULT_FEE = 1000; // 10%

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        // Deploy Mock contracts
        _deployMockContracts();

        // Generate addresses
        _generateAddresses();

        // Deploy contracts
        _deployContracts();

        // Label contracts
        labelAll();
    }

    function _deployMockContracts() internal {
        oeth = IERC20(address(new MockERC20("Origin ETH", "OETH", 18)));
        weth = IERC20(address(new MockERC20("Wrapped ETH", "WETH", 18)));
        vault = IOriginVault(address(new MockVault(IERC20(oeth))));
        strategy = IStrategy(address(new MockStrategy(IERC20(oeth))));
    }

    function _generateAddresses() internal {
        // Users and multisigs
        alice = makeAddr("alice");
        deployer = makeAddr("deployer");
        feeCollector = makeAddr("fee collector");

        operator = makeAddr("OPERATOR");
        governor = makeAddr("GOVERNOR");
    }

    function _deployContracts() internal {
        vm.startPrank(deployer);

        // --- Deploy Proxy
        originARMProxy = new Proxy();

        // --- Deploy OriginARM implementation
        originARM = new OriginARM(address(oeth), address(weth), address(vault), CLAIM_DELAY);

        // Initialization requires 1e12 liquid assets to mint to dead address.
        // Deployer approve the proxy to transfer 1e12 liquid assets.
        weth.approve(address(originARMProxy), 1e12);
        // Mint 1e12 liquid assets to the deployer.
        deal(address(weth), deployer, 1e12);

        // --- Initialize the proxy
        originARMProxy.initialize(
            address(originARM),
            governor,
            abi.encodeWithSelector(
                OriginARM.initialize.selector, "Origin ARM", "OARM", operator, DEFAULT_FEE, feeCollector, address(0)
            )
        );

        vm.stopPrank();

        // --- Set the proxy as the OriginARM
        originARM = OriginARM(address(originARMProxy));

        // set prices
        vm.prank(governor);
        originARM.setPrices(992 * 1e33, 1001 * 1e33);
    }
}
