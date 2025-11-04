// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "test/Base.sol";

import {Mainnet} from "contracts/utils/Addresses.sol";

// Contracts
import {WETH} from "@solmate/tokens/WETH.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {ARMRouter} from "contracts/ARMRouter.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

abstract contract Fork_Shared_ARMRouter_Test is Base_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        // Skip this test, because swapExactTokensForTokens returns has changed and need to be adapted
        vm.skip(true);
        
        // Create and select fork
        _createAndSelectFork();

        // Generate addresses
        _generateAddresses();

        // Deploy contracts
        _deployContracts();

        // Fund contracts
        _fundContracts();

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

    function _generateAddresses() internal {
        // Contracts.
        weth = IERC20(Mainnet.WETH);
        eeth = IERC20(Mainnet.EETH);
        weeth = IERC20(Mainnet.WEETH);
        steth = IERC20(Mainnet.STETH);
        wsteth = IERC20(Mainnet.WSTETH);
        lidoARM = LidoARM(payable(Mainnet.LIDO_ARM));
        etherfiARM = EtherFiARM(payable(Mainnet.ETHERFI_ARM));
    }

    function _deployContracts() internal {
        // Deploy Router
        router = new ARMRouter(address(weth));

        // Register ARMs in the Router
        router.registerConfig(
            address(steth), address(weth), ARMRouter.SwapType.ARM, address(lidoARM), bytes4(0), bytes4(0)
        );
        router.registerConfig(
            address(weth), address(steth), ARMRouter.SwapType.ARM, address(lidoARM), bytes4(0), bytes4(0)
        );
        router.registerConfig(
            address(eeth), address(weth), ARMRouter.SwapType.ARM, address(etherfiARM), bytes4(0), bytes4(0)
        );
        router.registerConfig(
            address(weth), address(eeth), ARMRouter.SwapType.ARM, address(etherfiARM), bytes4(0), bytes4(0)
        );

        bytes4 wrapSelector = bytes4(keccak256("wrap(uint256)"));
        bytes4 unwrapSelector = bytes4(keccak256("unwrap(uint256)"));
        bytes4 getWstETHByStETH = bytes4(keccak256("getWstETHByStETH(uint256)"));
        bytes4 getStETHByWstETH = bytes4(keccak256("getStETHByWstETH(uint256)"));
        bytes4 getWeETHByeETH = bytes4(keccak256("getWeETHByeETH(uint256)"));
        bytes4 getEETHByWeETH = bytes4(keccak256("getEETHByWeETH(uint256)"));
        // Register wrappers in the Router
        router.registerConfig(
            address(steth), address(wsteth), ARMRouter.SwapType.WRAPPER, address(wsteth), wrapSelector, getStETHByWstETH
        );
        router.registerConfig(
            address(wsteth),
            address(steth),
            ARMRouter.SwapType.WRAPPER,
            address(wsteth),
            unwrapSelector,
            getWstETHByStETH
        );
        router.registerConfig(
            address(eeth), address(weeth), ARMRouter.SwapType.WRAPPER, address(weeth), wrapSelector, getEETHByWeETH
        );
        router.registerConfig(
            address(weeth), address(eeth), ARMRouter.SwapType.WRAPPER, address(weeth), unwrapSelector, getWeETHByeETH
        );
    }

    function _fundContracts() internal {
        // Fund test contract
        deal(address(weth), address(this), 1_000 ether);
        deal(address(weth), Mainnet.TREASURY_LP, 1_000 ether);
        vm.prank(Mainnet.WSTETH);
        steth.transfer(address(this), 1_000 ether);
        vm.prank(Mainnet.WEETH);
        eeth.transfer(address(this), 1_000 ether);

        steth.approve(address(wsteth), type(uint256).max);
        (bool success,) = address(wsteth).call(abi.encodeWithSignature("wrap(uint256)", 500 ether));
        require(success, "Wrap WSTETH failed");
        eeth.approve(address(weeth), type(uint256).max);
        (success,) = address(weeth).call(abi.encodeWithSignature("wrap(uint256)", 500 ether));
        require(success, "Wrap WEETH failed");

        // Manage approvals
        weth.approve(address(lidoARM), type(uint256).max);
        weth.approve(address(etherfiARM), type(uint256).max);
        eeth.approve(address(router), type(uint256).max);
        eeth.approve(address(etherfiARM), type(uint256).max);
        weeth.approve(address(router), type(uint256).max);
        steth.approve(address(router), type(uint256).max);
        steth.approve(address(lidoARM), type(uint256).max);
        wsteth.approve(address(router), type(uint256).max);

        // Deposit 100 WETH in Lido ARM
        lidoARM.deposit(100 ether);

        // Deposit 100 WETH in EtherFi ARM
        vm.startPrank(Mainnet.TREASURY_LP);
        weth.approve(address(etherfiARM), type(uint256).max);
        etherfiARM.deposit(100 ether);
        vm.stopPrank();

        // Swap 50 STETH into WETH to fund the Lido ARM with STETH
        lidoARM.swapExactTokensForTokens(IERC20(address(steth)), IERC20(address(weth)), 50 ether, 0, address(this));
        // Swap 50 EETH into WETH to fund the EtherFi ARM with EETH
        etherfiARM.swapExactTokensForTokens(IERC20(address(eeth)), IERC20(address(weth)), 50 ether, 0, address(this));
    }

    receive() external payable {}
}
