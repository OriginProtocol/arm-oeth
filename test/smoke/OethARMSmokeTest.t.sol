// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {AbstractSmokeTest} from "./AbstractSmokeTest.sol";

import {IERC20} from "contracts/Interfaces.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {OriginARM} from "contracts/OriginARM.sol";

contract Fork_OriginARM_Smoke_Test is AbstractSmokeTest {
    IERC20 BAD_TOKEN = IERC20(makeAddr("bad token"));

    IERC20 weth;
    IERC20 oeth;
    Proxy proxy;
    OriginARM originARM;
    address operator;

    function setUp() public {
        oeth = IERC20(resolver.resolve("OETH"));
        weth = IERC20(resolver.resolve("WETH"));
        operator = resolver.resolve("OPERATOR");

        vm.label(address(weth), "WETH");
        vm.label(address(oeth), "OETH");
        vm.label(address(operator), "OPERATOR");

        proxy = Proxy(payable(deployManager.getDeployment("OETH_ARM")));
        originARM = OriginARM(deployManager.getDeployment("OETH_ARM"));

        _dealWETH(address(originARM), 100 ether);
        _dealOETH(address(originARM), 100 ether);

        // Only fuzz from this address. Big speedup on fork.
        targetSender(address(this));
    }

    ////////////////////////////////////////////////////
    /// --- HELPERS
    ////////////////////////////////////////////////////
    function _dealWETH(address to, uint256 amount) internal {
        deal(address(weth), to, amount);
    }

    // Helper functions to deal tokens from whales, because oeth is rebasing, so deal() doesn't work
    function _dealOETH(address to, uint256 amount) internal {
        vm.prank(Mainnet.WOETH);
        oeth.transfer(to, amount);
    }

    ////////////////////////////////////////////////////
    /// --- INITIAL CONFIG
    ////////////////////////////////////////////////////
    function test_initialConfig() external view {
        // Ownership and fees
        assertEq(originARM.name(), "Origin ARM", "Name");
        assertEq(originARM.symbol(), "ARM-WETH-OETH", "Symbol");
        assertEq(originARM.owner(), Mainnet.TIMELOCK, "Owner");
        assertEq(originARM.operator(), Mainnet.ARM_RELAYER, "Operator");
        assertEq(originARM.feeCollector(), Mainnet.ARM_BUYBACK, "Fee collector");
        assertEq((100 * uint256(originARM.fee())) / originARM.FEE_SCALE(), 20, "Performance fee as a percentage");

        // Assets
        assertEq(address(originARM.token0()), address(weth), "token0");
        assertEq(address(originARM.token1()), address(oeth), "token1");
        assertEq(originARM.liquidityAsset(), Mainnet.WETH, "liquidity asset");
        assertEq(originARM.baseAsset(), Mainnet.OETH, "base asset");
        assertEq(originARM.asset(), Mainnet.WETH, "ERC-4626 asset");

        // Prices
        assertNotEq(originARM.crossPrice(), 0, "cross price");
        assertNotEq(originARM.traderate0(), 0, "traderate0");
        assertNotEq(originARM.traderate1(), 0, "traderate1");

        // Redemption
        assertEq(address(originARM.vault()), Mainnet.OETH_VAULT, "OETH Vault");
        assertEq(originARM.claimDelay(), 10 minutes, "claim delay");
    }

    ////////////////////////////////////////////////////
    /// --- SWAP TESTS
    ////////////////////////////////////////////////////

    function test_swap_exact_oeth_for_weth() external {
        // trader sells OETH and buys WETH, the ARM buys OETH as a
        // 4 bps discount
        _swapExactTokensForTokens(oeth, weth, 0.9996e36, 100 ether);
        // 10 bps discount
        _swapExactTokensForTokens(oeth, weth, 0.999e36, 1e15);
        // 20 bps discount
        _swapExactTokensForTokens(oeth, weth, 0.998e36, 1 ether);
    }

    function test_swap_exact_weth_for_oeth() external {
        // For this test, we need to set the cross price to 0.9999e36, which requires
        // moving out all OETH from the ARM.
        vm.startPrank(address(originARM));
        oeth.transfer(address(this), oeth.balanceOf(address(originARM)));
        vm.stopPrank();
        vm.prank(Mainnet.TIMELOCK);
        originARM.setCrossPrice(0.9999e36);

        // trader buys OETH and sells WETH, the ARM sells OETH at a
        // 0.5 bps discount
        _swapExactTokensForTokens(weth, oeth, 0.99995e36, 10 ether);
        // 1 bps discount
        _swapExactTokensForTokens(weth, oeth, 0.9999e36, 100 ether);
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 price, uint256 amountIn) internal {
        uint256 expectedOut;
        if (inToken == weth) {
            // Trader is buying stETH and selling WETH
            // the ARM is selling stETH and buying WETH
            deal(address(weth), address(this), 1_000_000 ether);
            _dealOETH(address(originARM), 1000 ether);

            expectedOut = amountIn * 1e36 / price;

            vm.prank(Mainnet.ARM_RELAYER);
            originARM.setPrices(price - 2e32, price);
        } else {
            // Trader is selling stETH and buying WETH
            // the ARM is buying stETH and selling WETH
            _dealOETH(address(this), 1000 ether);
            deal(address(weth), address(originARM), 1_000_000 ether);

            expectedOut = amountIn * price / 1e36;

            vm.prank(Mainnet.ARM_RELAYER);
            originARM.setPrices(price, 1e36);
        }
        // Approve the ARM to transfer the input token of the swap.
        inToken.approve(address(originARM), amountIn);

        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));

        originARM.swapExactTokensForTokens(inToken, outToken, amountIn, 0, address(this));

        assertApproxEqAbs(inToken.balanceOf(address(this)), startIn - amountIn, 2, "In actual");
        assertApproxEqAbs(outToken.balanceOf(address(this)), startOut + expectedOut, 2, "Out actual");
    }

    function test_swap_oeth_for_exact_weth() external {
        // trader sells OETH and buys WETH, the ARM buys OETH at a
        // 4 bps discount
        _swapTokensForExactTokens(oeth, weth, 0.9996e36, 10 ether);
        // 10 bps discount
        _swapTokensForExactTokens(oeth, weth, 0.999e36, 100 ether);
        // 50 bps discount
        _swapTokensForExactTokens(oeth, weth, 0.995e36, 10 ether);
    }

    function test_swap_weth_for_exact_oeth() external {
        // For this test, we need to set the cross price to 0.9999e36, which requires
        // moving out all OETH from the ARM.
        vm.startPrank(address(originARM));
        oeth.transfer(address(this), oeth.balanceOf(address(originARM)));
        vm.stopPrank();
        vm.prank(Mainnet.TIMELOCK);
        originARM.setCrossPrice(0.9999e36);

        // trader buys OETH and sells WETH, the ARM sells OETH at a
        // 0.5 bps discount
        _swapTokensForExactTokens(weth, oeth, 0.99995e36, 10 ether);
        // 1 bps discount
        _swapTokensForExactTokens(weth, oeth, 0.9999e36, 100 ether);
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 price, uint256 amountOut) internal {
        uint256 expectedIn;
        if (inToken == weth) {
            // Trader is buying stETH and selling WETH
            // the ARM is selling stETH and buying WETH
            deal(address(weth), address(this), 1_000_000 ether);
            _dealOETH(address(originARM), 1000 ether);

            expectedIn = amountOut * price / 1e36;

            vm.prank(Mainnet.ARM_RELAYER);
            originARM.setPrices(price - 2e32, price);
        } else {
            // Trader is selling stETH and buying WETH
            // the ARM is buying stETH and selling WETH
            _dealOETH(address(this), 1000 ether);
            deal(address(weth), address(originARM), 1_000_000 ether);

            expectedIn = amountOut * 1e36 / price + 3;

            vm.prank(Mainnet.ARM_RELAYER);
            originARM.setPrices(price, 1e36);
        }
        // Approve the ARM to transfer the input token of the swap.
        inToken.approve(address(originARM), expectedIn + 10000);

        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));

        originARM.swapTokensForExactTokens(inToken, outToken, amountOut, 3 * amountOut, address(this));

        assertApproxEqAbs(inToken.balanceOf(address(this)), startIn - expectedIn, 3, "In actual");
        assertApproxEqAbs(outToken.balanceOf(address(this)), startOut + amountOut, 3, "Out actual");
    }

    function test_wrongInTokenExactIn() external {
        vm.expectRevert("ARM: Invalid in token");
        originARM.swapExactTokensForTokens(BAD_TOKEN, oeth, 10 ether, 0, address(this));
        vm.expectRevert("ARM: Invalid in token");
        originARM.swapExactTokensForTokens(BAD_TOKEN, weth, 10 ether, 0, address(this));
    }

    function test_wrongOutTokenExactIn() external {
        vm.expectRevert("ARM: Invalid out token");
        originARM.swapTokensForExactTokens(weth, BAD_TOKEN, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid out token");
        originARM.swapTokensForExactTokens(oeth, BAD_TOKEN, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid out token");
        originARM.swapTokensForExactTokens(weth, weth, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid out token");
        originARM.swapTokensForExactTokens(oeth, oeth, 10 ether, 10 ether, address(this));
    }

    function test_wrongInTokenExactOut() external {
        vm.expectRevert("ARM: Invalid in token");
        originARM.swapTokensForExactTokens(BAD_TOKEN, oeth, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid in token");
        originARM.swapTokensForExactTokens(BAD_TOKEN, weth, 10 ether, 10 ether, address(this));
    }

    function test_wrongOutTokenExactOut() external {
        vm.expectRevert("ARM: Invalid out token");
        originARM.swapTokensForExactTokens(weth, BAD_TOKEN, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid out token");
        originARM.swapTokensForExactTokens(oeth, BAD_TOKEN, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid out token");
        originARM.swapTokensForExactTokens(weth, weth, 10 ether, 10 ether, address(this));
        vm.expectRevert("ARM: Invalid out token");
        originARM.swapTokensForExactTokens(oeth, oeth, 10 ether, 10 ether, address(this));
    }

    ////////////////////////////////////////////////////
    /// --- AUTHORIZATION
    ////////////////////////////////////////////////////
    function test_unauthorizedAccess() external {
        address RANDOM_ADDRESS = vm.randomAddress();
        vm.startPrank(RANDOM_ADDRESS);

        // Proxy's restricted methods.
        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.setOwner(RANDOM_ADDRESS);

        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.initialize(address(this), address(this), "");

        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.upgradeTo(address(this));

        vm.expectRevert("ARM: Only owner can call this function.");
        proxy.upgradeToAndCall(address(this), "");

        // Implementation's restricted methods.
        vm.expectRevert("ARM: Only owner can call this function.");
        originARM.setOwner(RANDOM_ADDRESS);
        vm.stopPrank();

        vm.expectRevert("ARM: Only owner can call this function.");
        vm.prank(operator);
        originARM.setOperator(operator);
    }

    function test_setOperator() external {
        vm.prank(Mainnet.TIMELOCK);
        originARM.setOperator(address(this));
        assertEq(originARM.operator(), address(this));
    }

    ////////////////////////////////////////////////////
    /// --- VAULT WITHDRAWALS
    ////////////////////////////////////////////////////
    function test_request_origin_withdrawal() external {
        _dealOETH(address(originARM), 10 ether);
        vm.prank(Mainnet.ARM_RELAYER);
        uint256 requestId = originARM.requestOriginWithdrawal(10 ether);
        assertNotEq(requestId, 0);
    }

    function test_claim_origin_withdrawal() external {
        // Cheat section
        // Deal OETH to the ARM, in order to have some asset to withdraw
        _dealOETH(address(originARM), 10 ether);
        // Deal WETH to this test account to mint OETH in the Vault, directly increasing
        // the Vault's liquidity doesn't work because of the "Backing supply liquidity error" check
        _dealWETH(address(this), 10_000 ether);
        (bool success,) =
            Mainnet.WETH.call(abi.encodeWithSignature("approve(address,uint256)", Mainnet.OETH_VAULT, 10_000 ether));
        require(success, "Approve failed");
        (success,) = Mainnet.OETH_VAULT.call(
            abi.encodeWithSignature("mint(address,uint256,uint256)", Mainnet.WETH, 10_000 ether, 0)
        );
        require(success, "Mint failed");
        // End cheat section

        // Request a withdrawal
        vm.prank(Mainnet.ARM_RELAYER);
        uint256 requestId = originARM.requestOriginWithdrawal(10 ether);

        // Fast forward time by 1 day to pass the claim delay
        vm.warp(block.timestamp + 1 days);

        // Claim the withdrawal
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;

        uint256 amountClaimed = originARM.claimOriginWithdrawals(requestIds);
        assertEq(amountClaimed, 10 ether);
    }
}
