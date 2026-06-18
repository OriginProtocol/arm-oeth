// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {CapManager} from "contracts/CapManager.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {Proxy} from "contracts/Proxy.sol";
import {StablesARM} from "contracts/StablesARM.sol";
import {PaxosAssetAdapter} from "contracts/adapters/PaxosAssetAdapter.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

contract Fork_StablesARM_Test is Test {
    IERC20 internal usdc;
    IERC20 internal usdg;
    IERC20 internal pyusd;
    Proxy internal armProxy;
    StablesARM internal stablesARM;
    CapManager internal capManager;
    PaxosAssetAdapter internal usdgAdapter;
    PaxosAssetAdapter internal pyusdAdapter;

    address internal deployer = makeAddr("deployer");
    address internal governor = makeAddr("governor");
    address internal operator = makeAddr("operator");
    address internal feeCollector = makeAddr("feeCollector");
    address internal alice = makeAddr("alice");
    address internal paxosRecipient = makeAddr("paxosRecipient");

    function setUp() external {
        require(vm.envExists("MAINNET_URL"), "MAINNET_URL not set");

        if (vm.envExists("FORK_BLOCK_NUMBER_MAINNET")) {
            vm.createSelectFork("mainnet", vm.envUint("FORK_BLOCK_NUMBER_MAINNET"));
        } else {
            vm.createSelectFork("mainnet");
        }

        usdc = IERC20(Mainnet.USDC);
        usdg = IERC20(Mainnet.USDG);
        pyusd = IERC20(Mainnet.PYUSD);

        vm.startPrank(deployer);
        armProxy = new Proxy();
        Proxy capManagerProxy = new Proxy();
        Proxy usdgAdapterProxy = new Proxy();
        Proxy pyusdAdapterProxy = new Proxy();

        StablesARM armImpl = new StablesARM(Mainnet.USDC, 10 minutes, 1e6, 100e6);
        CapManager capManagerImpl = new CapManager(address(armProxy));
        PaxosAssetAdapter usdgAdapterImpl = new PaxosAssetAdapter(address(armProxy), Mainnet.USDG, Mainnet.USDC);
        PaxosAssetAdapter pyusdAdapterImpl = new PaxosAssetAdapter(address(armProxy), Mainnet.PYUSD, Mainnet.USDC);

        deal(Mainnet.USDC, deployer, 1000);
        usdc.approve(address(armProxy), 1000);
        armProxy.initialize(
            address(armImpl),
            governor,
            abi.encodeWithSelector(
                StablesARM.initialize.selector,
                "StablesARM",
                "ARM-USDC-Stables",
                operator,
                2000,
                feeCollector,
                address(capManagerProxy)
            )
        );
        capManagerProxy.initialize(
            address(capManagerImpl), governor, abi.encodeWithSelector(CapManager.initialize.selector, operator)
        );
        usdgAdapterProxy.initialize(
            address(usdgAdapterImpl),
            governor,
            abi.encodeWithSelector(PaxosAssetAdapter.initialize.selector, operator, paxosRecipient)
        );
        pyusdAdapterProxy.initialize(
            address(pyusdAdapterImpl),
            governor,
            abi.encodeWithSelector(PaxosAssetAdapter.initialize.selector, operator, paxosRecipient)
        );
        vm.stopPrank();

        stablesARM = StablesARM(payable(address(armProxy)));
        capManager = CapManager(address(capManagerProxy));
        usdgAdapter = PaxosAssetAdapter(address(usdgAdapterProxy));
        pyusdAdapter = PaxosAssetAdapter(address(pyusdAdapterProxy));

        vm.startPrank(governor);
        capManager.setTotalAssetsCap(1_000_000e6);
        stablesARM.addBaseAsset(
            Mainnet.USDG,
            address(usdgAdapter),
            0.998e36,
            1e36,
            type(uint128).max,
            type(uint128).max,
            0.999e36,
            true
        );
        stablesARM.addBaseAsset(
            Mainnet.PYUSD,
            address(pyusdAdapter),
            0.998e36,
            1e36,
            type(uint128).max,
            type(uint128).max,
            0.999e36,
            true
        );
        vm.stopPrank();
    }

    function test_mainnetTokenDecimalsAndInitialAccounting() external view {
        assertEq(usdc.decimals(), 6, "USDC decimals");
        assertEq(usdg.decimals(), 6, "USDG decimals");
        assertEq(pyusd.decimals(), 6, "PYUSD decimals");
        assertEq(stablesARM.decimals(), 6, "ARM decimals");
        assertEq(stablesARM.minTotalSupply(), 1000, "min total supply");
        assertEq(stablesARM.totalSupply(), 1000, "total supply");
        assertEq(stablesARM.totalAssets(), 1000, "total assets");
    }

    function test_depositAndDirectSwapsUseSixDecimals() external {
        deal(Mainnet.USDC, alice, 1_100e6);
        deal(Mainnet.USDG, alice, 100e6);
        deal(Mainnet.PYUSD, alice, 100e6);

        vm.startPrank(alice);
        usdc.approve(address(stablesARM), 1_100e6);
        usdg.approve(address(stablesARM), 100e6);
        pyusd.approve(address(stablesARM), 100e6);

        uint256 shares = stablesARM.deposit(1_000e6);
        assertEq(shares, 1_000e6, "deposit shares");

        deal(Mainnet.USDG, address(stablesARM), 100e6);

        uint256[] memory usdgForUsdc =
            stablesARM.swapExactTokensForTokens(usdg, usdc, 100e6, 0, alice);
        assertEq(usdgForUsdc[1], 99_800_000, "USDG out");

        uint256[] memory pyusdForUsdc =
            stablesARM.swapExactTokensForTokens(pyusd, usdc, 100e6, 0, alice);
        assertEq(pyusdForUsdc[1], 99_800_000, "PYUSD out");

        uint256[] memory usdcForUsdg =
            stablesARM.swapExactTokensForTokens(usdc, usdg, 100e6, 0, alice);
        assertEq(usdcForUsdg[1], 100e6, "USDC to USDG out");
        vm.stopPrank();
    }

    function test_paxosSettlementFlow() external {
        deal(Mainnet.USDG, address(stablesARM), 100e6);

        vm.prank(operator);
        stablesARM.requestBaseAssetRedeem(Mainnet.USDG, 100e6);
        assertEq(usdg.balanceOf(address(usdgAdapter)), 100e6, "adapter USDG");

        vm.prank(operator);
        usdgAdapter.submitPaxosRedeem(100e6, keccak256("USDG-PAXOS-REDEMPTION"));
        assertEq(usdg.balanceOf(paxosRecipient), 100e6, "paxos USDG");
        assertEq(usdgAdapter.settlingShares(), 100e6, "settling shares");

        deal(Mainnet.USDC, address(usdgAdapter), 100e6);

        vm.prank(operator);
        (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived) =
            stablesARM.claimBaseAssetRedeem(Mainnet.USDG, 100e6);
        assertEq(sharesClaimed, 100e6, "shares claimed");
        assertEq(assetsExpected, 100e6, "assets expected");
        assertEq(assetsReceived, 100e6, "assets received");
        assertEq(usdc.balanceOf(address(stablesARM)), 100e6 + 1000, "ARM USDC");
    }
}
