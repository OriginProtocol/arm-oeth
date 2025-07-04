// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {AbstractSmokeTest} from "./AbstractSmokeTest.sol";

import {IERC20, IStETHWithdrawal} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {console} from "forge-std/console.sol";

contract Fork_LidoARM_Smoke_Test is AbstractSmokeTest {
    IERC20 BAD_TOKEN = IERC20(makeAddr("bad token"));

    IERC20 weth;
    IERC20 steth;
    Proxy proxy;
    LidoARM lidoARM;
    CapManager capManager;
    address operator;

    function setUp() public {
        weth = IERC20(resolver.resolve("WETH"));
        steth = IERC20(resolver.resolve("STETH"));
        operator = resolver.resolve("OPERATOR");

        vm.label(address(weth), "WETH");
        vm.label(address(steth), "stETH");
        vm.label(address(operator), "OPERATOR");

        proxy = Proxy(payable(deployManager.getDeployment("LIDO_ARM")));
        lidoARM = LidoARM(payable(deployManager.getDeployment("LIDO_ARM")));
        capManager = CapManager(deployManager.getDeployment("LIDO_ARM_CAP_MAN"));

        // Only fuzz from this address. Big speedup on fork.
        targetSender(address(this));
    }

    function test_initialConfig() external view {
        assertEq(lidoARM.name(), "Lido ARM", "Name");
        assertEq(lidoARM.symbol(), "ARM-WETH-stETH", "Symbol");
        assertEq(lidoARM.owner(), Mainnet.TIMELOCK, "Owner");
        assertEq(lidoARM.operator(), Mainnet.ARM_RELAYER, "Operator");
        assertEq(lidoARM.feeCollector(), Mainnet.STRATEGIST, "Fee collector");
        assertEq((100 * uint256(lidoARM.fee())) / lidoARM.FEE_SCALE(), 20, "Performance fee as a percentage");
        // LidoLiquidityManager
        assertEq(address(lidoARM.lidoWithdrawalQueue()), Mainnet.LIDO_WITHDRAWAL, "Lido withdrawal queue");
        assertEq(address(lidoARM.steth()), Mainnet.STETH, "stETH");
        assertEq(address(lidoARM.weth()), Mainnet.WETH, "WETH");
        assertEq(lidoARM.liquidityAsset(), Mainnet.WETH, "liquidity asset");
        assertEq(lidoARM.claimDelay(), 10 minutes, "claim delay");
        assertEq(lidoARM.crossPrice(), 0.9999e36, "cross price");

        assertEq(capManager.accountCapEnabled(), false, "account cap enabled");
        assertEq(capManager.operator(), Mainnet.ARM_RELAYER, "Operator");
        assertEq(capManager.arm(), address(lidoARM), "arm");
    }

    function test_swap_exact_steth_for_weth() external {
        // trader sells stETH and buys WETH, the ARM buys stETH as a
        // 4 bps discount
        _swapExactTokensForTokens(steth, weth, 0.9996e36, 100 ether);
        // 10 bps discount
        _swapExactTokensForTokens(steth, weth, 0.999e36, 1e15);
        // 20 bps discount
        _swapExactTokensForTokens(steth, weth, 0.998e36, 1 ether);
    }

    function test_swap_exact_weth_for_steth() external {
        // trader buys stETH and sells WETH, the ARM sells stETH at a
        // 0.5 bps discount
        _swapExactTokensForTokens(weth, steth, 0.99995e36, 10 ether);
        // 1 bps discount
        _swapExactTokensForTokens(weth, steth, 0.9999e36, 100 ether);
    }

    function test_swapTokensForExactTokens() external {
        // trader sells stETH and buys WETH, the ARM buys stETH at a
        // 4 bps discount
        _swapTokensForExactTokens(steth, weth, 0.9996e36, 10 ether);
        // 10 bps discount
        _swapTokensForExactTokens(steth, weth, 0.999e36, 100 ether);
        // 50 bps discount
        _swapTokensForExactTokens(steth, weth, 0.995e36, 10 ether);
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 price, uint256 amountIn) internal {
        uint256 expectedOut;
        if (inToken == weth) {
            // Trader is buying stETH and selling WETH
            // the ARM is selling stETH and buying WETH
            deal(address(weth), address(this), 1_000_000 ether);
            _dealStETH(address(lidoARM), 1000 ether);

            expectedOut = amountIn * 1e36 / price;

            vm.prank(Mainnet.ARM_RELAYER);
            lidoARM.setPrices(price - 2e32, price);
        } else {
            // Trader is selling stETH and buying WETH
            // the ARM is buying stETH and selling WETH
            _dealStETH(address(this), 1000 ether);
            deal(address(weth), address(lidoARM), 1_000_000 ether);

            expectedOut = amountIn * price / 1e36;

            vm.prank(Mainnet.ARM_RELAYER);
            uint256 sellPrice = price < 0.9997e36 ? 0.9999e36 : price + 2e32;
            lidoARM.setPrices(price, sellPrice);
        }
        // Approve the ARM to transfer the input token of the swap.
        inToken.approve(address(lidoARM), amountIn);

        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));

        lidoARM.swapExactTokensForTokens(inToken, outToken, amountIn, 0, address(this));

        assertApproxEqAbs(inToken.balanceOf(address(this)), startIn - amountIn, 2, "In actual");
        assertApproxEqAbs(outToken.balanceOf(address(this)), startOut + expectedOut, 2, "Out actual");
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 price, uint256 amountOut) internal {
        uint256 expectedIn;
        if (inToken == weth) {
            // Trader is buying stETH and selling WETH
            // the ARM is selling stETH and buying WETH
            deal(address(weth), address(this), 1_000_000 ether);
            _dealStETH(address(lidoARM), 1000 ether);

            expectedIn = amountOut * price / 1e36;

            vm.prank(Mainnet.ARM_RELAYER);
            lidoARM.setPrices(price - 2e32, price);
        } else {
            // Trader is selling stETH and buying WETH
            // the ARM is buying stETH and selling WETH
            _dealStETH(address(this), 1000 ether);
            deal(address(weth), address(lidoARM), 1_000_000 ether);
            // _dealWETH(address(lidoARM), 1000 ether);

            expectedIn = amountOut * 1e36 / price + 3;

            vm.prank(Mainnet.ARM_RELAYER);
            uint256 sellPrice = price < 0.9997e36 ? 0.9999e36 : price + 2e32;
            lidoARM.setPrices(price, sellPrice);
        }
        // Approve the ARM to transfer the input token of the swap.
        inToken.approve(address(lidoARM), expectedIn + 10000);
        console.log("Approved Lido ARM to spend %d", inToken.allowance(address(this), address(lidoARM)));
        console.log("In token balance: %d", inToken.balanceOf(address(this)));

        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));

        lidoARM.swapTokensForExactTokens(inToken, outToken, amountOut, 3 * amountOut, address(this));

        assertApproxEqAbs(inToken.balanceOf(address(this)), startIn - expectedIn, 2, "In actual");
        assertApproxEqAbs(outToken.balanceOf(address(this)), startOut + amountOut, 2, "Out actual");
    }

    function test_proxy_unauthorizedAccess() external {
        address RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;
        vm.startPrank(RANDOM_ADDRESS);

        // Proxy's restricted methods.
        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.setOwner(RANDOM_ADDRESS);

        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.initialize(address(this), address(this), "");

        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.upgradeTo(address(this));

        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.upgradeToAndCall(address(this), "");

        // Implementation's restricted methods.
        vm.expectRevert("OSwap: Only owner can call this function.");
        lidoARM.setOwner(RANDOM_ADDRESS);
    }

    // TODO replace _dealStETH with just deal
    function _dealStETH(address to, uint256 amount) internal {
        vm.prank(0xEB9c1CE881F0bDB25EAc4D74FccbAcF4Dd81020a);
        steth.transfer(to, amount + 2);
        // deal(address(steth), to, amount);
    }

    /* Operator Tests */

    function test_setOperator() external {
        vm.prank(Mainnet.TIMELOCK);
        lidoARM.setOperator(address(this));
        assertEq(lidoARM.operator(), address(this));
    }

    function test_nonOwnerCannotSetOperator() external {
        vm.expectRevert("ARM: Only owner can call this function.");
        vm.prank(operator);
        lidoARM.setOperator(operator);
    }

    error InvalidInitialization();

    // Can not be called again after reinitialized by the deploy script
    function test_registerLidoWithdrawalRequests() external {
        vm.expectRevert(InvalidInitialization.selector);
        vm.prank(operator);
        lidoARM.registerLidoWithdrawalRequests();
    }

    function test_lidoWithdrawalRequests() external view {
        uint256 totalAmountRequested = 0;
        uint256[] memory requestIds = IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL).getWithdrawalRequests(address(lidoARM));
        // Get the status of all the withdrawal requests. eg amount, owner, claimed status
        IStETHWithdrawal.WithdrawalRequestStatus[] memory statuses =
            IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL).getWithdrawalStatus(requestIds);

        console.log("Got %d withdrawal requests", requestIds.length);

        for (uint256 i = 0; i < requestIds.length; i++) {
            assertEq(lidoARM.lidoWithdrawalRequests(requestIds[i]), statuses[i].amountOfStETH);
            totalAmountRequested += statuses[i].amountOfStETH;
        }

        assertEq(totalAmountRequested, lidoARM.lidoWithdrawalQueueAmount());
    }
}
