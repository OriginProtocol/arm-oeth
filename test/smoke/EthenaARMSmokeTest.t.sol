// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Foundry
import {console} from "forge-std/console.sol";

import {AbstractSmokeTest} from "./AbstractSmokeTest.sol";

import {IERC20} from "contracts/Interfaces.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {IStakedUSDe} from "contracts/Interfaces.sol";

contract Fork_EthenaARM_Smoke_Test is AbstractSmokeTest {
    IERC20 BAD_TOKEN = IERC20(makeAddr("bad token"));

    IERC20 usde;
    IERC20 susde;
    Proxy armProxy;
    EthenaARM ethenaARM;
    CapManager capManager;
    address operator;

    function setUp() public {
        usde = IERC20(Mainnet.USDE);
        susde = IERC20(Mainnet.SUSDE);
        operator = resolver.resolve("OPERATOR");

        vm.label(address(usde), "USDE");
        vm.label(address(susde), "SUSDE");
        vm.label(address(operator), "OPERATOR");

        armProxy = Proxy(payable(deployManager.getDeployment("ETHENA_ARM")));
        ethenaARM = EthenaARM(payable(deployManager.getDeployment("ETHENA_ARM")));
        capManager = CapManager(deployManager.getDeployment("ETHENA_ARM_CAP_MAN"));

        vm.prank(ethenaARM.owner());
        ethenaARM.setOwner(Mainnet.TIMELOCK);
    }

    function test_initialConfig() external view {
        assertEq(ethenaARM.name(), "Ethena Staked USDe ARM", "Name");
        assertEq(ethenaARM.symbol(), "ARM-sUSDe-USDe", "Symbol");
        assertEq(ethenaARM.owner(), Mainnet.TIMELOCK, "Owner");
        assertEq(ethenaARM.operator(), Mainnet.ARM_RELAYER, "Operator");
        assertEq(ethenaARM.feeCollector(), Mainnet.BUYBACK_OPERATOR, "Fee collector");
        assertEq((100 * uint256(ethenaARM.fee())) / ethenaARM.FEE_SCALE(), 20, "Performance fee as a percentage");

        assertEq(address(ethenaARM.susde()), Mainnet.SUSDE, "sUSDe");
        assertEq(address(ethenaARM.usde()), Mainnet.USDE, "USDE");
        assertEq(ethenaARM.liquidityAsset(), Mainnet.USDE, "liquidity asset");
        assertEq(ethenaARM.asset(), Mainnet.USDE, "ERC-4626 asset");
        assertEq(ethenaARM.claimDelay(), 10 minutes, "claim delay");
        assertEq(ethenaARM.crossPrice(), 0.999e36, "cross price");

        assertEq(capManager.accountCapEnabled(), true, "account cap enabled");
        assertEq(capManager.totalAssetsCap(), 100000 ether, "total assets cap");
        assertEq(capManager.liquidityProviderCaps(Mainnet.TREASURY_LP), 20000 ether, "liquidity provider cap");
        assertEq(capManager.operator(), Mainnet.ARM_RELAYER, "Operator");
        assertEq(capManager.arm(), address(ethenaARM), "arm");
    }

    function test_swap_exact_susde_for_usde() external {
        // trader sells sUSDe and buys USDe, the ARM buys sUSDe as a
        // 20 bps discount
        _swapExactTokensForTokens(susde, usde, 0.9980e36, 100 ether);
        // 30 bps discount
        _swapExactTokensForTokens(susde, usde, 0.9970e36, 1e15);
        // 40 bps discount
        _swapExactTokensForTokens(susde, usde, 0.9960e36, 1 ether);
    }

    function test_swap_exact_usde_for_susde() external {
        // trader buys sUSDe and sells USDe, the ARM sells sUSDe at a
        // 0.5 bps discount
        _swapExactTokensForTokens(usde, susde, 0.99995e36, 10 ether);
        // 1 bps discount
        _swapExactTokensForTokens(usde, susde, 0.9999e36, 100 ether);
    }

    function test_swapTokensForExactTokens() external {
        // trader sells sUSDe and buys USDe, the ARM buys sUSDe at a
        // 20 bps discount
        _swapTokensForExactTokens(susde, usde, 0.9980e36, 10 ether);
        // 30 bps discount
        _swapTokensForExactTokens(susde, usde, 0.9970e36, 100 ether);
        // 50 bps discount
        _swapTokensForExactTokens(susde, usde, 0.9950e36, 10 ether);
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 price, uint256 amountIn) internal {
        uint256 expectedOut;
        if (inToken == usde) {
            // Trader is buying sUSDe and selling USDE
            // the ARM is selling sUSDe and buying USDE
            deal(address(usde), address(this), 1_000_000 ether);
            _dealSUSDe(address(ethenaARM), 1000 ether);

            expectedOut = amountIn * 1e36 / price;
            expectedOut = IStakedUSDe(address(susde)).convertToShares(expectedOut);

            vm.prank(Mainnet.ARM_RELAYER);
            ethenaARM.setPrices(0.9900e36, price);
        } else {
            // Trader is selling sUSDe and buying USDE
            // the ARM is buying sUSDe and selling USDE
            _dealSUSDe(address(this), 1000 ether);
            deal(address(usde), address(ethenaARM), 1_000_000 ether);

            expectedOut = amountIn * price / 1e36;
            expectedOut = IStakedUSDe(address(susde)).convertToAssets(expectedOut);

            vm.prank(Mainnet.ARM_RELAYER);
            uint256 sellPrice = price < 0.9997e36 ? 0.9999e36 : price + 2e32;
            ethenaARM.setPrices(price, sellPrice);
        }
        // Approve the ARM to transfer the input token of the swap.
        inToken.approve(address(ethenaARM), amountIn);

        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));

        ethenaARM.swapExactTokensForTokens(inToken, outToken, amountIn, 0, address(this));

        assertApproxEqAbs(inToken.balanceOf(address(this)), startIn - amountIn, 2, "In actual");
        assertApproxEqAbs(outToken.balanceOf(address(this)), startOut + expectedOut, 2, "Out actual");
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 price, uint256 amountOut) internal {
        uint256 expectedIn;
        if (inToken == usde) {
            // Trader is buying sUSDe and selling USDE
            // the ARM is selling sUSDe and buying USDE
            deal(address(usde), address(this), 1_000_000 ether);
            _dealSUSDe(address(ethenaARM), 1000 ether);

            expectedIn = IStakedUSDe(address(susde)).convertToAssets(amountOut) * price / 1e36;

            vm.prank(Mainnet.ARM_RELAYER);
            ethenaARM.setPrices(0.9900e36, price);
        } else {
            // Trader is selling sUSDe and buying USDE
            // the ARM is buying sUSDe and selling USDE
            _dealSUSDe(address(this), 1000 ether);
            deal(address(usde), address(ethenaARM), 1_000_000 ether);
            // _dealWETH(address(ethenaARM), 1000 ether);

            expectedIn = IStakedUSDe(address(susde)).convertToShares(amountOut) * 1e36 / price + 3;

            vm.prank(Mainnet.ARM_RELAYER);
            uint256 sellPrice = price < 0.9997e36 ? 0.9999e36 : price + 2e32;
            ethenaARM.setPrices(price, sellPrice);
        }
        // Approve the ARM to transfer the input token of the swap.
        inToken.approve(address(ethenaARM), expectedIn + 10000);
        console.log("Approved Lido ARM to spend %d", inToken.allowance(address(this), address(ethenaARM)));
        console.log("In token balance: %d", inToken.balanceOf(address(this)));

        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));

        ethenaARM.swapTokensForExactTokens(inToken, outToken, amountOut, 3 * amountOut, address(this));

        assertApproxEqAbs(inToken.balanceOf(address(this)), startIn - expectedIn, 2, "In actual");
        assertApproxEqAbs(outToken.balanceOf(address(this)), startOut + amountOut, 2, "Out actual");
    }

    function _dealSUSDe(address to, uint256 amount) internal {
        vm.prank(0x211Cc4DD073734dA055fbF44a2b4667d5E5fE5d2);
        susde.transfer(to, amount + 2);
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
        ethenaARM.setOwner(RANDOM_ADDRESS);
    }

    /* Operator Tests */
    function test_setOperator() external {
        vm.prank(Mainnet.TIMELOCK);
        ethenaARM.setOperator(address(this));
        assertEq(ethenaARM.operator(), address(this));
    }

    function test_nonOwnerCannotSetOperator() external {
        vm.expectRevert("ARM: Only owner can call this function.");
        vm.prank(operator);
        ethenaARM.setOperator(operator);
    }

    function test_request_ethena_withdrawal_operator() external {
        // trader sells sUSDe and buys USDE, the ARM buys sUSDe as a 20 bps discount
        _swapExactTokensForTokens(susde, usde, 0.9980e36, 100 ether);

        // Operator requests an Ethena withdrawal
        vm.prank(Mainnet.ARM_RELAYER);
        ethenaARM.requestBaseWithdrawal(10 ether);
    }

    function test_request_ethena_withdrawal_owner() external {
        // trader sells sUSDe and buys USDE, the ARM buys sUSDe as a 20 bps discount
        _swapExactTokensForTokens(susde, usde, 0.9980e36, 100 ether);

        // Owner requests an Ethena withdrawal
        vm.prank(Mainnet.TIMELOCK);
        ethenaARM.requestBaseWithdrawal(10 ether);
    }

    function test_claim_ethena_request_with_delay() external {
        // trader sells sUSDe and buys USDE, the ARM buys sUSDe as a 20 bps discount
        _swapExactTokensForTokens(susde, usde, 0.9980e36, 100 ether);

        // Owner requests an Ethena withdrawal
        uint256 nextUnstakerIndex = ethenaARM.nextUnstakerIndex();
        vm.prank(Mainnet.TIMELOCK);
        ethenaARM.requestBaseWithdrawal(10 ether);

        skip(7 days);

        // Claim the withdrawal
        address unstaker = ethenaARM.unstakers(nextUnstakerIndex);
        vm.prank(Mainnet.ARM_RELAYER);
        ethenaARM.claimBaseWithdrawals(unstaker);
    }

    // Allocate to market
    function test_allocate_AAVEMarket_withoutYield() external {
        _swapExactTokensForTokens(usde, susde, 0.9999e36, 1_000 ether);

        vm.prank(Mainnet.ARM_RELAYER);
        ethenaARM.setARMBuffer(5000); // 50%

        uint256 balanceBefore = usde.balanceOf(address(ethenaARM));
        ethenaARM.allocate();

        vm.prank(Mainnet.ARM_RELAYER);
        ethenaARM.setActiveMarket(address(0));
        uint256 balanceAfter = usde.balanceOf(address(ethenaARM));

        assertApproxEqAbs(balanceAfter, balanceBefore, 2, "Allocated amount");
    }

    function test_allocate_AAVEMarket_withYield() external {
        _swapExactTokensForTokens(usde, susde, 0.9999e36, 1_000 ether);

        vm.prank(Mainnet.ARM_RELAYER);
        ethenaARM.setARMBuffer(5000); // 50%

        // Allocate
        uint256 balanceBefore = usde.balanceOf(address(ethenaARM));
        ethenaARM.allocate();

        // Simulate yield by transferring aUSDE to the active market
        address aUSDE = 0x4F5923Fc5FD4a93352581b38B7cD26943012DECF;
        address whale = 0xc468315a2df54f9c076bD5Cfe5002BA211F74CA6;
        address activeMarket = ethenaARM.activeMarket();
        vm.prank(whale);
        IERC20(aUSDE).transfer(activeMarket, 10 ether);

        // Deallocate
        vm.prank(Mainnet.ARM_RELAYER);
        ethenaARM.setActiveMarket(address(0));
        uint256 balanceAfter = usde.balanceOf(address(ethenaARM));

        assertGt(balanceAfter, balanceBefore, "Allocated amount with yield");
    }
}
