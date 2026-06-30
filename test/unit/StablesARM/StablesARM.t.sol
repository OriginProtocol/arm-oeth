// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {AbstractARM} from "contracts/AbstractARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {Proxy} from "contracts/Proxy.sol";
import {StablesARM} from "contracts/StablesARM.sol";
import {PaxosAssetAdapter} from "contracts/adapters/PaxosAssetAdapter.sol";

contract Unit_StablesARM_Test is Test {
    address internal deployer = makeAddr("deployer");
    address internal governor = makeAddr("governor");
    address internal operator = makeAddr("operator");
    address internal feeCollector = makeAddr("feeCollector");
    address internal alice = makeAddr("alice");
    address internal paxosRecipient = makeAddr("paxosRecipient");

    MockERC20 internal usdc;
    MockERC20 internal usdg;
    MockERC20 internal pyusd;
    Proxy internal armProxy;
    Proxy internal capManagerProxy;
    Proxy internal usdgAdapterProxy;
    Proxy internal pyusdAdapterProxy;
    StablesARM internal stablesARM;
    CapManager internal capManager;
    PaxosAssetAdapter internal usdgAdapter;
    PaxosAssetAdapter internal pyusdAdapter;

    function setUp() external {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdg = new MockERC20("Global Dollar", "USDG", 6);
        pyusd = new MockERC20("PayPal USD", "PYUSD", 6);

        vm.startPrank(deployer);
        armProxy = new Proxy();
        capManagerProxy = new Proxy();
        usdgAdapterProxy = new Proxy();
        pyusdAdapterProxy = new Proxy();

        StablesARM armImpl = new StablesARM(address(usdc), 10 minutes, 1e6, 100e6);
        CapManager capManagerImpl = new CapManager(address(armProxy));
        PaxosAssetAdapter usdgAdapterImpl = new PaxosAssetAdapter(address(armProxy), address(usdg), address(usdc));
        PaxosAssetAdapter pyusdAdapterImpl = new PaxosAssetAdapter(address(armProxy), address(pyusd), address(usdc));

        usdc.mint(deployer, 1000);
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
            address(usdg), address(usdgAdapter), 0.998e36, 1e36, type(uint128).max, type(uint128).max, 0.999e36, true
        );
        stablesARM.addBaseAsset(
            address(pyusd), address(pyusdAdapter), 0.998e36, 1e36, type(uint128).max, type(uint128).max, 0.999e36, true
        );
        vm.stopPrank();
    }

    function test_initializesWithSixDecimalDeadShares() external view {
        assertEq(stablesARM.decimals(), 6, "LP decimals");
        assertEq(stablesARM.minTotalSupply(), 1000, "min total supply");
        assertEq(stablesARM.totalSupply(), 1000, "total supply");
        assertEq(stablesARM.totalAssets(), 1000, "total assets");
        assertEq(usdc.balanceOf(address(stablesARM)), 1000, "USDC balance");
    }

    function test_depositAndRedeemUseSixDecimalAssets() external {
        usdc.mint(alice, 100e6);

        vm.startPrank(alice);
        usdc.approve(address(stablesARM), 100e6);
        uint256 shares = stablesARM.deposit(100e6);
        assertEq(shares, 100e6, "shares");
        assertEq(stablesARM.balanceOf(alice), 100e6, "alice shares");

        (uint256 requestId, uint256 assets) = stablesARM.requestRedeem(25e6);
        assertEq(assets, 25e6, "request assets");
        vm.warp(block.timestamp + 10 minutes);
        stablesARM.claimRedeem(requestId);
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), 25e6, "redeemed USDC");
        assertEq(stablesARM.balanceOf(alice), 75e6, "remaining shares");
    }

    function test_capsUseSixDecimalAssets() external {
        vm.startPrank(governor);
        capManager.setTotalAssetsCap(50e6);
        capManager.setAccountCapEnabled(true);
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        capManager.setLiquidityProviderCaps(accounts, 40e6);
        vm.stopPrank();

        usdc.mint(alice, 41e6);
        vm.startPrank(alice);
        usdc.approve(address(stablesARM), 41e6);
        vm.expectRevert("LPC: LP cap exceeded");
        stablesARM.deposit(41e6);

        stablesARM.deposit(40e6);
        assertEq(capManager.liquidityProviderCaps(alice), 0, "cap consumed");
        vm.stopPrank();
    }

    function test_swapExactUSDGForUSDCAccruesFees() external {
        _depositUSDC(alice, 1_000e6);
        usdg.mint(alice, 100e6);

        vm.startPrank(alice);
        usdg.approve(address(stablesARM), 100e6);
        uint256[] memory amounts =
            stablesARM.swapExactTokensForTokens(IERC20(address(usdg)), IERC20(address(usdc)), 100e6, 0, alice);
        vm.stopPrank();

        assertEq(amounts[0], 100e6, "amount in");
        assertEq(amounts[1], 99_800_000, "amount out");
        assertGt(stablesARM.feesAccrued(), 0, "fees accrued");
    }

    function test_swapExactUSDCForUSDG() external {
        usdg.mint(address(stablesARM), 100e6);
        usdc.mint(alice, 100e6);

        vm.startPrank(alice);
        usdc.approve(address(stablesARM), 100e6);
        uint256[] memory amounts =
            stablesARM.swapExactTokensForTokens(IERC20(address(usdc)), IERC20(address(usdg)), 100e6, 0, alice);
        vm.stopPrank();

        assertEq(amounts[0], 100e6, "amount in");
        assertEq(amounts[1], 100e6, "amount out");
        assertEq(usdg.balanceOf(alice), 100e6, "alice USDG");
    }

    function test_swapExactPYUSDForUSDC() external {
        _depositUSDC(alice, 1_000e6);
        pyusd.mint(alice, 100e6);

        vm.startPrank(alice);
        pyusd.approve(address(stablesARM), 100e6);
        uint256[] memory amounts =
            stablesARM.swapExactTokensForTokens(IERC20(address(pyusd)), IERC20(address(usdc)), 100e6, 0, alice);
        vm.stopPrank();

        assertEq(amounts[0], 100e6, "amount in");
        assertEq(amounts[1], 99_800_000, "amount out");
    }

    function test_requestSubmitAndClaimBaseRedeemThroughPaxosSettlement() external {
        usdg.mint(address(stablesARM), 100e6);

        vm.prank(operator);
        (uint256 sharesRequested, uint256 assetsExpected) = stablesARM.requestBaseAssetRedeem(address(usdg), 100e6);
        assertEq(sharesRequested, 100e6, "shares requested");
        assertEq(assetsExpected, 100e6, "assets expected");
        assertEq(usdg.balanceOf(address(usdgAdapter)), 100e6, "adapter USDG");
        assertEq(usdgAdapter.pendingShares(), 100e6, "pending shares");

        bytes32 paxosRedemptionId = keccak256("paxos-redemption-id");
        vm.prank(operator);
        usdgAdapter.submitPaxosRedeem(100e6, paxosRedemptionId);
        assertEq(usdg.balanceOf(paxosRecipient), 100e6, "paxos USDG");
        assertEq(usdgAdapter.pendingShares(), 0, "pending submitted");
        assertEq(usdgAdapter.settlingShares(), 100e6, "settling shares");

        usdc.mint(address(usdgAdapter), 100e6);
        vm.prank(operator);
        (uint256 sharesClaimed,, uint256 assetsReceived) = stablesARM.claimBaseAssetRedeem(address(usdg), 100e6);
        assertEq(sharesClaimed, 100e6, "shares claimed");
        assertEq(assetsReceived, 100e6, "assets received");
        assertEq(usdc.balanceOf(address(stablesARM)), 100e6 + 1000, "ARM USDC");
        assertEq(usdgAdapter.settlingShares(), 0, "settling claimed");
    }

    function test_claimBaseRedeemRevertsBeforePaxosSettlementArrives() external {
        usdg.mint(address(stablesARM), 100e6);

        vm.prank(operator);
        stablesARM.requestBaseAssetRedeem(address(usdg), 100e6);
        vm.prank(operator);
        usdgAdapter.submitPaxosRedeem(100e6, keccak256("paxos-redemption-id"));

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaxosAssetAdapter.InsufficientSettledAssets.selector, 100e6, 0));
        stablesARM.claimBaseAssetRedeem(address(usdg), 100e6);
    }

    function test_submitPaxosRedeemRequiresConfiguredRecipient() external {
        PaxosAssetAdapter newAdapterImpl = new PaxosAssetAdapter(address(this), address(usdg), address(usdc));
        Proxy newAdapterProxy = new Proxy();
        newAdapterProxy.initialize(
            address(newAdapterImpl),
            governor,
            abi.encodeWithSelector(PaxosAssetAdapter.initialize.selector, operator, address(0))
        );
        PaxosAssetAdapter unconfiguredAdapter = PaxosAssetAdapter(address(newAdapterProxy));

        usdg.mint(address(this), 1e6);
        usdg.approve(address(unconfiguredAdapter), 1e6);
        unconfiguredAdapter.requestRedeem(1e6);

        vm.prank(operator);
        vm.expectRevert(PaxosAssetAdapter.PaxosRecipientNotConfigured.selector);
        unconfiguredAdapter.submitPaxosRedeem(1e6, keccak256("paxos-redemption-id"));
    }

    function test_addPeggedBaseAssetRejectsMismatchedDecimals() external {
        MockERC20 badBase = new MockERC20("Bad Stable", "BAD", 18);
        PaxosAssetAdapter badAdapter = new PaxosAssetAdapter(address(armProxy), address(usdg), address(usdc));

        vm.prank(governor);
        vm.expectRevert(AbstractARM.InvalidAssetDecimals.selector);
        stablesARM.addBaseAsset(
            address(badBase), address(badAdapter), 0.998e36, 1e36, type(uint128).max, type(uint128).max, 0.999e36, true
        );
    }

    function test_allocateWithoutActiveMarketReverts() external {
        vm.expectRevert("ARM: no active market");
        stablesARM.allocate();
    }

    function _depositUSDC(address account, uint256 amount) internal {
        usdc.mint(account, amount);
        vm.startPrank(account);
        usdc.approve(address(stablesARM), amount);
        stablesARM.deposit(amount);
        vm.stopPrank();
    }
}
