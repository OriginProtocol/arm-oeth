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
    /// @dev 0.998e36 = 0.998 USDC per base asset, the automation's minimum buy price.
    uint256 internal constant MIN_BUY_PRICE = 0.998e36;
    /// @dev 0.99995e36 = 0.99995 USDC per base asset, the automation's maximum buy price.
    uint256 internal constant MAX_BUY_PRICE = 0.99995e36;
    /// @dev 0.99997e36 = 0.99997 USDC per base asset, the automation's minimum sell price.
    uint256 internal constant MIN_SELL_PRICE = 0.99997e36;
    /// @dev 1e36 = 1 USDC per base asset, the automation's maximum sell price.
    uint256 internal constant MAX_SELL_PRICE = 1e36;

    IERC20 usdc;
    IERC20 pyusd;
    IERC20 usdg;
    Proxy armProxy;
    MultiAssetARM usdcARM;
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

        armProxy = Proxy(payable(resolver.resolve("USDC_ARM")));
        usdcARM = MultiAssetARM(payable(resolver.resolve("USDC_ARM")));
        pyusdAdapter = PaxosAssetAdapter(resolver.resolve("USDC_ARM_PYUSD_ADAPTER"));
        usdgAdapter = PaxosAssetAdapter(resolver.resolve("USDC_ARM_USDG_ADAPTER"));
        capManager = CapManager(resolver.resolve("USDC_ARM_CAP_MAN"));
    }

    function test_initialConfig() external view {
        assertEq(usdcARM.name(), "USDC ARM", "Name");
        assertEq(usdcARM.symbol(), "ARM-USDC", "Symbol");
        assertEq(usdcARM.owner(), Mainnet.MULTISIG_2_OF_8, "Owner");
        assertEq(usdcARM.operator(), operator, "Operator");
        assertEq(usdcARM.feeCollector(), Mainnet.BUYBACK_OPERATOR, "Fee collector");
        assertEq(usdcARM.fee(), 2000, "Performance fee");
        assertEq(usdcARM.liquidityAsset(), Mainnet.USDC, "liquidity asset");
        assertEq(usdcARM.claimDelay(), 10 minutes, "claim delay");

        // PYUSD adapter
        assertEq(pyusdAdapter.arm(), address(usdcARM), "PYUSD adapter arm");
        assertEq(address(pyusdAdapter.baseAsset()), Mainnet.PYUSD, "PYUSD adapter base asset");
        assertEq(pyusdAdapter.asset(), Mainnet.USDC, "PYUSD adapter liquidity asset");
        assertEq(pyusdAdapter.owner(), Mainnet.MULTISIG_2_OF_8, "PYUSD adapter owner");
        assertEq(pyusdAdapter.operator(), operator, "PYUSD adapter operator");
        assertNotEq(pyusdAdapter.paxosRecipient(), address(0), "PYUSD adapter paxos recipient");
        assertEq(
            address(pyusdAdapter), resolver.resolve("USD_ARM_PYUSD_ADAPTER"), "PYUSD adapter proxy reused from USD ARM"
        );

        // USDG adapter
        assertEq(usdgAdapter.arm(), address(usdcARM), "USDG adapter arm");
        assertEq(address(usdgAdapter.baseAsset()), Mainnet.USDG, "USDG adapter base asset");
        assertEq(usdgAdapter.asset(), Mainnet.USDC, "USDG adapter liquidity asset");
        assertEq(usdgAdapter.owner(), Mainnet.MULTISIG_2_OF_8, "USDG adapter owner");
        assertEq(usdgAdapter.operator(), operator, "USDG adapter operator");
        assertNotEq(usdgAdapter.paxosRecipient(), address(0), "USDG adapter paxos recipient");
        assertEq(
            address(usdgAdapter), resolver.resolve("USD_ARM_USDG_ADAPTER"), "USDG adapter proxy reused from USD ARM"
        );

        address[] memory baseAssets = usdcARM.getBaseAssets();
        _assertBaseAssetListed(baseAssets, Mainnet.PYUSD, "PYUSD listed as base asset");
        _assertBaseAssetListed(baseAssets, Mainnet.USDG, "USDG listed as base asset");

        assertEq(capManager.arm(), address(usdcARM), "cap manager arm");
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
            uint128 sellPrice,,,
            uint128 crossPrice,,
            bool peggedToLiquidityAsset,
            uint8 baseAssetDecimals,
            address adapter
        ) = usdcARM.baseAssetConfigs(baseAsset);

        assertGe(buyPrice, MIN_BUY_PRICE, string.concat(label, " minimum buy price"));
        assertLe(buyPrice, MAX_BUY_PRICE, string.concat(label, " maximum buy price"));
        assertGe(sellPrice, MIN_SELL_PRICE, string.concat(label, " minimum sell price"));
        assertLe(sellPrice, MAX_SELL_PRICE, string.concat(label, " maximum sell price"));
        assertEq(crossPrice, 0.99997e36, string.concat(label, " cross price"));
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
        deal(address(usdc), address(usdcARM), 1_000_000e6);
        deal(address(pyusd), address(this), 1_000e6);

        pyusd.approve(address(usdcARM), amountIn);

        // The deployment registers base assets with zero swap liquidity, so the operator must set
        // the buy/sell amounts before any swap is possible.
        vm.prank(operator);
        usdcARM.setPrices(address(pyusd), 0.998e36, 1e36, type(uint128).max, type(uint128).max);

        uint256 startIn = pyusd.balanceOf(address(this));
        uint256 startOut = usdc.balanceOf(address(this));

        usdcARM.swapExactTokensForTokens(pyusd, usdc, amountIn, 0, address(this));

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
        deal(address(usdg), address(usdcARM), 1_000e6);
        deal(address(usdc), address(this), 1_000e6);

        usdc.approve(address(usdcARM), amountIn);

        // The deployment registers base assets with zero swap liquidity, so the operator must set
        // the buy/sell amounts before any swap is possible.
        vm.prank(operator);
        usdcARM.setPrices(address(usdg), 0.998e36, 1e36, type(uint128).max, type(uint128).max);

        uint256 startIn = usdc.balanceOf(address(this));
        uint256 startOut = usdg.balanceOf(address(this));

        usdcARM.swapExactTokensForTokens(usdc, usdg, amountIn, 0, address(this));

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
        uint256 pendingSharesBefore = adapter.pendingShares();
        uint256 settlingSharesBefore = adapter.settlingShares();
        (,,,,, uint128 pendingRedeemAssetsBefore,,,) = usdcARM.baseAssetConfigs(address(baseAsset));

        // Give the ARM base asset inventory (as if bought from traders).
        deal(address(baseAsset), address(usdcARM), shares);

        uint256 totalAssetsBefore = usdcARM.totalAssets();
        uint256 armUsdcBefore = usdc.balanceOf(address(usdcARM));

        // 1. Operator queues the base assets for Paxos redemption. The adapter pulls them from the ARM.
        vm.prank(operator);
        usdcARM.requestBaseAssetRedeem(address(baseAsset), shares);
        assertEq(adapter.pendingShares(), pendingSharesBefore + shares, "pending shares after request");
        assertGe(baseAsset.balanceOf(address(adapter)), shares, "adapter base balance after request");

        // 2. Owner configures the Paxos deposit address (mocked as a test address).
        address paxosRecipient = makeAddr("paxosRecipient");
        vm.prank(Mainnet.MULTISIG_2_OF_8);
        adapter.setPaxosRecipient(paxosRecipient);

        // 3. Operator submits the queued base assets to Paxos.
        vm.prank(operator);
        adapter.submitPaxosRedeem(shares, bytes32("id"));
        assertEq(baseAsset.balanceOf(paxosRecipient), shares, "paxos recipient base balance");
        assertEq(adapter.pendingShares(), pendingSharesBefore, "pending shares after submit");
        assertEq(adapter.settlingShares(), settlingSharesBefore + shares, "settling shares after submit");

        // 4. Mock the off-chain Paxos settlement: USDC lands on the adapter 1:1.
        deal(address(usdc), address(adapter), shares);

        // 5. Operator claims the settled USDC back into the ARM.
        vm.prank(operator);
        usdcARM.claimBaseAssetRedeem(address(baseAsset), shares);

        assertEq(adapter.pendingShares(), pendingSharesBefore, "pending shares after claim");
        assertEq(adapter.settlingShares(), settlingSharesBefore, "settling shares after claim");
        assertEq(usdc.balanceOf(address(usdcARM)), armUsdcBefore + shares, "ARM USDC balance after claim");
        (,,,,, uint128 pendingRedeemAssets,,,) = usdcARM.baseAssetConfigs(address(baseAsset));
        assertEq(pendingRedeemAssets, pendingRedeemAssetsBefore, "pending redeem assets after claim");
        assertGe(usdcARM.totalAssets(), totalAssetsBefore, "total assets not decreased");
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
        usdcARM.setOwner(RANDOM_ADDRESS);
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
