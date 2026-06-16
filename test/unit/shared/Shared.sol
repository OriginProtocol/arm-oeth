// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "test/Base.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OriginARM} from "contracts/OriginARM.sol";

// Interfaces
import {IERC20, IOriginVault} from "contracts/Interfaces.sol";

// Mocks
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockVault} from "test/unit/mocks/MockVault.sol";

abstract contract Unit_Shared_Test is Base_Test_ {
    uint256 public constant CLAIM_DELAY = 10 minutes;
    uint256 public constant DEFAULT_FEE = 2_000; // 20%
    uint256 public constant MIN_SHARES_TO_REDEEM = 1e7;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();

        _generateAddresses();
        _deployMockContracts();
        _deployContracts();
        labelAll();
    }

    function _generateAddresses() internal {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        deployer = makeAddr("deployer");
        feeCollector = makeAddr("fee collector");
        operator = makeAddr("operator");
        governor = makeAddr("governor");
    }

    function _deployMockContracts() internal {
        os = IERC20(address(new MockERC20("Origin Token", "OTOKEN", 18)));
        weth = IERC20(address(new MockERC20("Wrapped Ether", "WETH", 18)));
        vault = IOriginVault(address(new MockVault(os, weth)));
    }

    function _deployContracts() internal {
        vm.startPrank(deployer);

        originARMProxy = new Proxy();
        originARM = new OriginARM(address(os), address(weth), address(vault), CLAIM_DELAY, MIN_SHARES_TO_REDEEM, 1e18);

        deal(address(weth), deployer, MIN_TOTAL_SUPPLY);
        weth.approve(address(originARMProxy), MIN_TOTAL_SUPPLY);

        originARMProxy.initialize(
            address(originARM),
            governor,
            abi.encodeWithSelector(
                OriginARM.initialize.selector, "Origin ARM", "OARM", operator, DEFAULT_FEE, feeCollector, address(0)
            )
        );

        vm.stopPrank();

        originARM = OriginARM(address(originARMProxy));
    }

    //////////////////////////////////////////////////////
    /// --- PRANK MODIFIERS
    //////////////////////////////////////////////////////
    modifier asOperator() {
        vm.startPrank(operator);
        _;
        vm.stopPrank();
    }

    modifier asNotGovernor() {
        vm.startPrank(randomAddrDiff(governor));
        _;
        vm.stopPrank();
    }

    modifier asNotOperatorNorGovernor() {
        vm.startPrank(randomAddrDiff(governor, operator));
        _;
        vm.stopPrank();
    }

    function randomAddrDiff(address _addr) public returns (address) {
        address _rand = vm.randomAddress();
        while (_rand == _addr) {
            _rand = vm.randomAddress();
        }
        return _rand;
    }

    function randomAddrDiff(address _addr1, address _addr2) public returns (address) {
        address _rand = vm.randomAddress();
        while (_rand == _addr1 || _rand == _addr2) {
            _rand = vm.randomAddress();
        }
        return _rand;
    }
}
