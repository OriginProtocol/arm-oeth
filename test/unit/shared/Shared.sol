// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "test/Base.sol";
import {Modifiers} from "test/unit/shared/Modifiers.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OriginARM} from "contracts/OriginARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IOriginVault} from "contracts/Interfaces.sol";
// Mocks
import {MockVault} from "test/unit/mocks/MockVault.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626Market} from "test/unit/mocks/MockERC4626Market.sol";

abstract contract Unit_Shared_Test is Base_Test_, Modifiers {
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
        market = IERC4626(address(new MockERC4626Market(IERC20(weth))));
        market2 = IERC4626(address(new MockERC4626Market(IERC20(weth))));
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
