// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {AbstractSmokeTest} from "./AbstractSmokeTest.sol";

import {IERC20, IEETHWithdrawal, IEETHWithdrawalNFT} from "contracts/Interfaces.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {console} from "forge-std/console.sol";

contract Fork_EtherFiARM_Smoke_Test is AbstractSmokeTest {
    IERC20 BAD_TOKEN = IERC20(makeAddr("bad token"));

    IERC20 weth;
    IERC20 eeth;
    Proxy armProxy;
    EtherFiARM etherFiARM;
    CapManager capManager;
    IEETHWithdrawalNFT etherfiWithdrawalNFT;
    address operator;

    function setUp() public {
        weth = IERC20(resolver.resolve("WETH"));
        eeth = IERC20(resolver.resolve("EETH"));
        operator = resolver.resolve("OPERATOR");

        vm.label(address(weth), "WETH");
        vm.label(address(eeth), "eETH");
        vm.label(address(operator), "OPERATOR");

        armProxy = Proxy(payable(deployManager.getDeployment("ETHER_FI_ARM")));
        etherFiARM = EtherFiARM(payable(deployManager.getDeployment("ETHER_FI_ARM")));
        capManager = CapManager(deployManager.getDeployment("ETHER_FI_ARM_CAP_MAN"));
        etherfiWithdrawalNFT = IEETHWithdrawalNFT(Mainnet.ETHERFI_WITHDRAWAL_NFT);

        // Only fuzz from this address. Big speedup on fork.
        targetSender(address(this));
    }

    function test_initialConfig() external view {
        assertEq(etherFiARM.name(), "Ether.fi ARM", "Name");
        assertEq(etherFiARM.symbol(), "ARM-WETH-eETH", "Symbol");
        assertEq(etherFiARM.owner(), Mainnet.TIMELOCK, "Owner");
        assertEq(etherFiARM.operator(), Mainnet.ARM_RELAYER, "Operator");
        assertEq(etherFiARM.feeCollector(), Mainnet.BUYBACK_OPERATOR, "Fee collector");
        assertEq((100 * uint256(etherFiARM.fee())) / etherFiARM.FEE_SCALE(), 20, "Performance fee as a percentage");
        // LidoLiquidityManager
        assertEq(address(etherFiARM.etherfiWithdrawalQueue()), Mainnet.ETHERFI_WITHDRAWAL, "Ether.fi withdrawal queue");
        assertEq(address(etherFiARM.eeth()), Mainnet.EETH, "eETH");
        assertEq(address(etherFiARM.weth()), Mainnet.WETH, "WETH");
        assertEq(etherFiARM.liquidityAsset(), Mainnet.WETH, "liquidity asset");
        assertEq(etherFiARM.asset(), Mainnet.WETH, "ERC-4626 asset");
        assertEq(etherFiARM.claimDelay(), 10 minutes, "claim delay");
        assertEq(etherFiARM.crossPrice(), 0.9998e36, "cross price");

        assertEq(capManager.accountCapEnabled(), true, "account cap enabled");
        assertEq(capManager.totalAssetsCap(), 250 ether, "total assets cap");
        assertEq(capManager.liquidityProviderCaps(Mainnet.TREASURY_LP), 250 ether, "liquidity provider cap");
        assertEq(capManager.operator(), Mainnet.ARM_RELAYER, "Operator");
        assertEq(capManager.arm(), address(etherFiARM), "arm");
    }

    function test_swap_exact_eeth_for_weth() external {
        // trader sells eETH and buys WETH, the ARM buys eETH as a
        // 4 bps discount
        _swapExactTokensForTokens(eeth, weth, 0.9996e36, 100 ether);
        // 10 bps discount
        _swapExactTokensForTokens(eeth, weth, 0.999e36, 1e15);
        // 20 bps discount
        _swapExactTokensForTokens(eeth, weth, 0.998e36, 1 ether);
    }

    function test_swap_exact_weth_for_eeth() external {
        // trader buys eETH and sells WETH, the ARM sells eETH at a
        // 0.5 bps discount
        _swapExactTokensForTokens(weth, eeth, 0.99995e36, 10 ether);
        // 1 bps discount
        _swapExactTokensForTokens(weth, eeth, 0.9999e36, 100 ether);
    }

    function test_swapTokensForExactTokens() external {
        // trader sells eETH and buys WETH, the ARM buys eETH at a
        // 4 bps discount
        _swapTokensForExactTokens(eeth, weth, 0.9996e36, 10 ether);
        // 10 bps discount
        _swapTokensForExactTokens(eeth, weth, 0.999e36, 100 ether);
        // 50 bps discount
        _swapTokensForExactTokens(eeth, weth, 0.995e36, 10 ether);
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 price, uint256 amountIn) internal {
        uint256 expectedOut;
        if (inToken == weth) {
            // Trader is buying eETH and selling WETH
            // the ARM is selling eETH and buying WETH
            deal(address(weth), address(this), 1_000_000 ether);
            _dealEETH(address(etherFiARM), 1000 ether);

            expectedOut = amountIn * 1e36 / price;

            vm.prank(Mainnet.ARM_RELAYER);
            etherFiARM.setPrices(price - 2e32, price);
        } else {
            // Trader is selling eETH and buying WETH
            // the ARM is buying eETH and selling WETH
            _dealEETH(address(this), 1000 ether);
            deal(address(weth), address(etherFiARM), 1_000_000 ether);

            expectedOut = amountIn * price / 1e36;

            vm.prank(Mainnet.ARM_RELAYER);
            uint256 sellPrice = price < 0.9997e36 ? 0.9999e36 : price + 2e32;
            etherFiARM.setPrices(price, sellPrice);
        }
        // Approve the ARM to transfer the input token of the swap.
        inToken.approve(address(etherFiARM), amountIn);

        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));

        etherFiARM.swapExactTokensForTokens(inToken, outToken, amountIn, 0, address(this));

        assertApproxEqAbs(inToken.balanceOf(address(this)), startIn - amountIn, 2, "In actual");
        assertApproxEqAbs(outToken.balanceOf(address(this)), startOut + expectedOut, 2, "Out actual");
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 price, uint256 amountOut) internal {
        uint256 expectedIn;
        if (inToken == weth) {
            // Trader is buying eETH and selling WETH
            // the ARM is selling eETH and buying WETH
            deal(address(weth), address(this), 1_000_000 ether);
            _dealEETH(address(etherFiARM), 1000 ether);

            expectedIn = amountOut * price / 1e36;

            vm.prank(Mainnet.ARM_RELAYER);
            etherFiARM.setPrices(price - 2e32, price);
        } else {
            // Trader is selling eETH and buying WETH
            // the ARM is buying eETH and selling WETH
            _dealEETH(address(this), 1000 ether);
            deal(address(weth), address(etherFiARM), 1_000_000 ether);
            // _dealWETH(address(etherFiARM), 1000 ether);

            expectedIn = amountOut * 1e36 / price + 3;

            vm.prank(Mainnet.ARM_RELAYER);
            uint256 sellPrice = price < 0.9997e36 ? 0.9999e36 : price + 2e32;
            etherFiARM.setPrices(price, sellPrice);
        }
        // Approve the ARM to transfer the input token of the swap.
        inToken.approve(address(etherFiARM), expectedIn + 10000);
        console.log("Approved Lido ARM to spend %d", inToken.allowance(address(this), address(etherFiARM)));
        console.log("In token balance: %d", inToken.balanceOf(address(this)));

        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));

        etherFiARM.swapTokensForExactTokens(inToken, outToken, amountOut, 3 * amountOut, address(this));

        assertApproxEqAbs(inToken.balanceOf(address(this)), startIn - expectedIn, 2, "In actual");
        assertApproxEqAbs(outToken.balanceOf(address(this)), startOut + amountOut, 2, "Out actual");
    }

    function test_proxy_unauthorizedAccess() external {
        address RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;
        vm.startPrank(RANDOM_ADDRESS);

        // Proxy's restricted methods.
        vm.expectRevert("ARM: Only owner can call this function.");
        armProxy.setOwner(RANDOM_ADDRESS);

        vm.expectRevert("ARM: Only owner can call this function.");
        armProxy.initialize(address(this), address(this), "");

        vm.expectRevert("ARM: Only owner can call this function.");
        armProxy.upgradeTo(address(this));

        vm.expectRevert("ARM: Only owner can call this function.");
        armProxy.upgradeToAndCall(address(this), "");

        // Implementation's restricted methods.
        vm.expectRevert("ARM: Only owner can call this function.");
        etherFiARM.setOwner(RANDOM_ADDRESS);
    }

    // TODO replace _dealEETH with just deal
    function _dealEETH(address to, uint256 amount) internal {
        vm.prank(0x22162DbBa43fE0477cdC5234E248264eC7C6EA7c);
        eeth.transfer(to, amount + 2);
        // deal(address(eeth), to, amount);
    }

    /* Operator Tests */

    function test_setOperator() external {
        vm.prank(Mainnet.TIMELOCK);
        etherFiARM.setOperator(address(this));
        assertEq(etherFiARM.operator(), address(this));
    }

    function test_nonOwnerCannotSetOperator() external {
        vm.expectRevert("ARM: Only owner can call this function.");
        vm.prank(operator);
        etherFiARM.setOperator(operator);
    }

    function test_request_etherfi_withdrawal_operator() external {
        // trader sells eETH and buys WETH, the ARM buys eETH as a 4 bps discount
        _swapExactTokensForTokens(eeth, weth, 0.9996e36, 100 ether);

        // Expected events
        vm.expectEmit(true, false, false, false, address(etherFiARM));
        emit EtherFiARM.RequestEtherFiWithdrawal(10 ether, 0);

        // Operator requests an Ether.fi withdrawal
        vm.prank(Mainnet.ARM_RELAYER);
        etherFiARM.requestEtherFiWithdrawal(10 ether);
    }

    function test_request_etherfi_withdrawal_owner() external {
        // trader sells eETH and buys WETH, the ARM buys eETH as a 4 bps discount
        _swapExactTokensForTokens(eeth, weth, 0.9996e36, 100 ether);

        // Expected events
        vm.expectEmit(true, false, false, false, address(etherFiARM));
        emit EtherFiARM.RequestEtherFiWithdrawal(10 ether, 0);

        // Owner requests an Ether.fi withdrawal
        vm.prank(Mainnet.TIMELOCK);
        etherFiARM.requestEtherFiWithdrawal(10 ether);
    }

    function test_claim_etherfi_request_with_delay() external {
        // trader sells eETH and buys WETH, the ARM buys eETH as a 4 bps discount
        _swapExactTokensForTokens(eeth, weth, 0.9996e36, 100 ether);

        // Owner requests an Ether.fi withdrawal
        vm.prank(Mainnet.TIMELOCK);
        uint256 requestId = etherFiARM.requestEtherFiWithdrawal(10 ether);

        // Process finalization on withdrawal queue
        // We cheat a bit here, because we don't follow the full finalization process it could fail
        // if there is not enough liquidity, but since the amount to claim is low, it should be fine
        vm.prank(0x0EF8fa4760Db8f5Cd4d993f3e3416f30f942D705);
        etherfiWithdrawalNFT.finalizeRequests(requestId);

        // Claim the withdrawal
        uint256[] memory requestIdArray = new uint256[](1);
        requestIdArray[0] = requestId;
        etherFiARM.claimEtherFiWithdrawals(requestIdArray);
    }
}
