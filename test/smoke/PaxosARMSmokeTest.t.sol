// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AbstractSmokeTest} from "./AbstractSmokeTest.sol";

import {IERC20} from "contracts/Interfaces.sol";
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {PaxosAssetAdapter} from "contracts/adapters/PaxosAssetAdapter.sol";
import {CapManager} from "contracts/CapManager.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

contract Fork_PaxosARM_Smoke_Test is AbstractSmokeTest {
    IERC20 usdc;
    IERC20 pyusd;
    IERC20 usdg;
    Proxy armProxy;
    MultiAssetARM usdARM;
    PaxosAssetAdapter pyusdAdapter;
    PaxosAssetAdapter usdgAdapter;
    CapManager capManager;
    address operator;

    function setUp() public override {
        super.setUp();
        usdc = IERC20(Mainnet.USDC);
        pyusd = IERC20(Mainnet.PYUSD);
        usdg = IERC20(Mainnet.USDG);
        operator = Mainnet.ARM_TALOS_RELAYER;

        vm.label(address(usdc), "USDC");
        vm.label(address(pyusd), "PYUSD");
        vm.label(address(usdg), "USDG");
        vm.label(address(operator), "OPERATOR");

        armProxy = Proxy(payable(resolver.resolve("USD_ARM")));
        usdARM = MultiAssetARM(payable(resolver.resolve("USD_ARM")));
        pyusdAdapter = PaxosAssetAdapter(resolver.resolve("USD_ARM_PYUSD_ADAPTER"));
        usdgAdapter = PaxosAssetAdapter(resolver.resolve("USD_ARM_USDG_ADAPTER"));
        capManager = CapManager(resolver.resolve("USD_ARM_CAP_MAN"));
    }

    function test_initialConfig() external view {
        assertEq(usdARM.name(), "USD ARM", "Name");
        assertEq(usdARM.symbol(), "ARM-USD", "Symbol");
        assertEq(usdARM.owner(), Mainnet.MULTISIG_2_OF_8, "Owner");
        assertEq(usdARM.operator(), operator, "Operator");
        assertEq(usdARM.feeCollector(), Mainnet.BUYBACK_OPERATOR, "Fee collector");
        assertEq(usdARM.fee(), 2000, "Performance fee");
        assertEq(usdARM.liquidityAsset(), Mainnet.USDC, "liquidity asset");
        assertEq(usdARM.claimDelay(), 10 minutes, "claim delay");

        // PYUSD adapter
        assertEq(pyusdAdapter.arm(), address(usdARM), "PYUSD adapter arm");
        assertEq(address(pyusdAdapter.baseAsset()), Mainnet.PYUSD, "PYUSD adapter base asset");
        assertEq(pyusdAdapter.asset(), Mainnet.USDC, "PYUSD adapter liquidity asset");
        assertEq(pyusdAdapter.owner(), Mainnet.MULTISIG_2_OF_8, "PYUSD adapter owner");
        assertEq(pyusdAdapter.operator(), operator, "PYUSD adapter operator");
        assertEq(pyusdAdapter.paxosRecipient(), Mainnet.PAXOS_RECIPIENT, "PYUSD adapter paxos recipient placeholder");
        assertEq(pyusdAdapter.pendingShares(), 0, "PYUSD adapter pending shares");
        assertEq(pyusdAdapter.settlingShares(), 0, "PYUSD adapter settling shares");

        // USDG adapter
        assertEq(usdgAdapter.arm(), address(usdARM), "USDG adapter arm");
        assertEq(address(usdgAdapter.baseAsset()), Mainnet.USDG, "USDG adapter base asset");
        assertEq(usdgAdapter.asset(), Mainnet.USDC, "USDG adapter liquidity asset");
        assertEq(usdgAdapter.owner(), Mainnet.MULTISIG_2_OF_8, "USDG adapter owner");
        assertEq(usdgAdapter.operator(), operator, "USDG adapter operator");
        assertEq(usdgAdapter.paxosRecipient(), Mainnet.PAXOS_RECIPIENT, "USDG adapter paxos recipient placeholder");
        assertEq(usdgAdapter.pendingShares(), 0, "USDG adapter pending shares");
        assertEq(usdgAdapter.settlingShares(), 0, "USDG adapter settling shares");

        address[] memory baseAssets = usdARM.getBaseAssets();
        _assertBaseAssetListed(baseAssets, Mainnet.PYUSD, "PYUSD listed as base asset");
        _assertBaseAssetListed(baseAssets, Mainnet.USDG, "USDG listed as base asset");

        assertEq(capManager.arm(), address(usdARM), "cap manager arm");
        assertEq(capManager.totalAssetsCap(), 100_000e6, "total assets cap");
        assertEq(capManager.accountCapEnabled(), true, "account cap enabled");
        assertEq(capManager.liquidityProviderCaps(Mainnet.TREASURY_LP), 100_000e6, "liquidity provider cap");
        assertEq(capManager.operator(), operator, "cap manager operator");
        assertEq(capManager.owner(), Mainnet.MULTISIG_2_OF_8, "cap manager owner");
    }

    function test_baseAssetConfigs() external view {
        _assertBaseAssetConfig(Mainnet.PYUSD, address(pyusdAdapter), "PYUSD");
        _assertBaseAssetConfig(Mainnet.USDG, address(usdgAdapter), "USDG");
    }

    function _assertBaseAssetConfig(address baseAsset, address expectedAdapter, string memory label) internal view {
        (
            uint128 buyPrice,
            uint128 sellPrice,
            uint128 buyLiquidityRemaining,
            uint128 sellLiquidityRemaining,
            uint128 crossPrice,
            uint128 pendingRedeemAssets,
            bool peggedToLiquidityAsset,
            uint8 baseAssetDecimals,
            address adapter
        ) = usdARM.baseAssetConfigs(baseAsset);

        assertEq(buyPrice, 0.998e36, string.concat(label, " buy price"));
        assertEq(sellPrice, 1e36, string.concat(label, " sell price"));
        assertEq(buyLiquidityRemaining, 0, string.concat(label, " buy liquidity remaining"));
        assertEq(sellLiquidityRemaining, 0, string.concat(label, " sell liquidity remaining"));
        assertEq(crossPrice, 0.99997e36, string.concat(label, " cross price"));
        assertEq(pendingRedeemAssets, 0, string.concat(label, " pending redeem assets"));
        assertEq(peggedToLiquidityAsset, true, string.concat(label, " pegged"));
        assertEq(baseAssetDecimals, 6, string.concat(label, " base asset decimals"));
        assertEq(adapter, expectedAdapter, string.concat(label, " adapter"));
    }

    function test_swap_exact_pyusd_for_usdc() external {
        // Trader sells PYUSD and buys USDC; the ARM buys PYUSD at a 20 bps discount (buy price
        // 0.998e36), so the trader receives amountIn * 0.998 USDC.
        uint256 amountIn = 100e6;
        uint256 expectedOut = amountIn * 0.998e36 / 1e36;

        // Give the ARM USDC inventory and the trader PYUSD. Deal directly - deposits from
        // arbitrary accounts are blocked by the CapManager's account caps.
        deal(address(usdc), address(usdARM), 1_000_000e6);
        deal(address(pyusd), address(this), 1_000e6);

        pyusd.approve(address(usdARM), amountIn);

        // The deployment registers base assets with zero swap liquidity, so the operator must set
        // the buy/sell amounts before any swap is possible.
        vm.prank(operator);
        usdARM.setPrices(address(pyusd), 0.998e36, 1e36, type(uint128).max, type(uint128).max);

        uint256 startIn = pyusd.balanceOf(address(this));
        uint256 startOut = usdc.balanceOf(address(this));

        usdARM.swapExactTokensForTokens(pyusd, usdc, amountIn, 0, address(this));

        assertEq(pyusd.balanceOf(address(this)), startIn - amountIn, "PYUSD in actual");
        assertEq(usdc.balanceOf(address(this)), startOut + expectedOut, "USDC out actual");
    }

    function test_swap_exact_usdc_for_usdg() external {
        // Trader sells USDC and buys USDG; the ARM sells USDG at par (sell price 1e36), so the
        // trader receives amountIn USDG.
        uint256 amountIn = 100e6;
        uint256 expectedOut = amountIn * 1e36 / 1e36;

        // Give the ARM USDG inventory and the trader USDC. Deal directly - deposits from
        // arbitrary accounts are blocked by the CapManager's account caps.
        deal(address(usdg), address(usdARM), 1_000e6);
        deal(address(usdc), address(this), 1_000e6);

        usdc.approve(address(usdARM), amountIn);

        // The deployment registers base assets with zero swap liquidity, so the operator must set
        // the buy/sell amounts before any swap is possible.
        vm.prank(operator);
        usdARM.setPrices(address(usdg), 0.998e36, 1e36, type(uint128).max, type(uint128).max);

        uint256 startIn = usdc.balanceOf(address(this));
        uint256 startOut = usdg.balanceOf(address(this));

        usdARM.swapExactTokensForTokens(usdc, usdg, amountIn, 0, address(this));

        assertEq(usdc.balanceOf(address(this)), startIn - amountIn, "USDC in actual");
        assertEq(usdg.balanceOf(address(this)), startOut + expectedOut, "USDG out actual");
    }

    function test_pyusd_paxos_settlement_cycle() external {
        _paxosSettlementCycle(pyusd, pyusdAdapter);
    }

    function test_usdg_paxos_settlement_cycle() external {
        _paxosSettlementCycle(usdg, usdgAdapter);
    }

    /// @dev Full off-chain Paxos redemption cycle: the ARM queues base assets in the adapter, the
    ///      operator submits them to the Paxos deposit address, Paxos settles USDC 1:1 to the
    ///      adapter (mocked with deal), and the operator claims the USDC back into the ARM.
    function _paxosSettlementCycle(IERC20 baseAsset, PaxosAssetAdapter adapter) internal {
        uint256 shares = 1_000e6;

        // Give the ARM base asset inventory (as if bought from traders).
        deal(address(baseAsset), address(usdARM), shares);

        uint256 totalAssetsBefore = usdARM.totalAssets();
        uint256 armUsdcBefore = usdc.balanceOf(address(usdARM));

        // 1. Operator queues the base assets for Paxos redemption. The adapter pulls them from the ARM.
        vm.prank(operator);
        usdARM.requestBaseAssetRedeem(address(baseAsset), shares);
        assertEq(adapter.pendingShares(), shares, "pending shares after request");
        assertEq(baseAsset.balanceOf(address(adapter)), shares, "adapter base balance after request");

        // 2. Owner configures the Paxos deposit address (mocked as a test address).
        address paxosRecipient = makeAddr("paxosRecipient");
        vm.prank(Mainnet.MULTISIG_2_OF_8);
        adapter.setPaxosRecipient(paxosRecipient);

        // 3. Operator submits the queued base assets to Paxos.
        vm.prank(operator);
        adapter.submitPaxosRedeem(shares, bytes32("id"));
        assertEq(baseAsset.balanceOf(paxosRecipient), shares, "paxos recipient base balance");
        assertEq(adapter.pendingShares(), 0, "pending shares after submit");
        assertEq(adapter.settlingShares(), shares, "settling shares after submit");

        // 4. Mock the off-chain Paxos settlement: USDC lands on the adapter 1:1.
        deal(address(usdc), address(adapter), shares);

        // 5. Operator claims the settled USDC back into the ARM.
        vm.prank(operator);
        usdARM.claimBaseAssetRedeem(address(baseAsset), shares);

        assertEq(adapter.pendingShares(), 0, "pending shares after claim");
        assertEq(adapter.settlingShares(), 0, "settling shares after claim");
        assertEq(usdc.balanceOf(address(usdARM)), armUsdcBefore + shares, "ARM USDC balance after claim");
        (,,,,, uint128 pendingRedeemAssets,,,) = usdARM.baseAssetConfigs(address(baseAsset));
        assertEq(pendingRedeemAssets, 0, "pending redeem assets after claim");
        assertGe(usdARM.totalAssets(), totalAssetsBefore, "total assets not decreased");
    }

    function test_proxy_unauthorizedAccess() external {
        address RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;
        vm.startPrank(RANDOM_ADDRESS);

        // Unlike the live legacy ARM proxies (which revert with a string), this proxy is deployed
        // from the current codebase, whose Ownable reverts with the OnlyOwner() custom error.
        bytes4 onlyOwnerError = bytes4(keccak256("OnlyOwner()"));

        // Proxy's restricted methods.
        vm.expectRevert(onlyOwnerError);
        armProxy.setOwner(RANDOM_ADDRESS);

        vm.expectRevert(onlyOwnerError);
        armProxy.initialize(address(this), address(this), "");

        vm.expectRevert(onlyOwnerError);
        armProxy.upgradeTo(address(this));

        vm.expectRevert(onlyOwnerError);
        armProxy.upgradeToAndCall(address(this), "");

        // Implementation's restricted methods.
        vm.expectRevert(onlyOwnerError);
        usdARM.setOwner(RANDOM_ADDRESS);
    }

    /// @dev Assert `expected` appears in the ARM's `getBaseAssets()` list. A membership check
    ///      rather than exact array equality keeps the assertion robust to registration order and
    ///      to additional base assets being registered by future deployments.
    function _assertBaseAssetListed(address[] memory baseAssets, address expected, string memory label) internal pure {
        bool found = false;
        for (uint256 i = 0; i < baseAssets.length; ++i) {
            if (baseAssets[i] == expected) {
                found = true;
                break;
            }
        }
        assertTrue(found, label);
    }
}
