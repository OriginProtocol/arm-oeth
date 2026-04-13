// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Utils
import {Mainnet} from "contracts/utils/Addresses.sol";

contract Fork_Concrete_LidoARM_SwapGasImpact_Test is Fork_Shared_Test_ {
    uint256 internal constant INITIAL_ARM_BALANCE = 1_000 ether;
    uint256 internal constant INITIAL_USER_BALANCE = 200 ether;
    uint256 internal constant BUY_PRICE = 0.9995e36;
    uint256 internal constant SELL_PRICE = 1.001e36;
    uint256 internal constant EXACT_IN = 100 ether;
    uint256 internal constant EXACT_OUT = 99.95 ether;

    Proxy internal noSwapFeeProxy;
    LidoARM internal noSwapFeeLidoARM;
    address internal noSwapFeeUser;
    address internal upgradedUser;

    function setUp() public override {
        super.setUp();

        noSwapFeeUser = makeAddr("noSwapFeeUser");
        upgradedUser = makeAddr("upgradedUser");

        noSwapFeeProxy = new Proxy();
        LidoARM noSwapFeeImpl = new LidoARM(address(steth), address(weth), Mainnet.LIDO_WITHDRAWAL, 10 minutes, 0, 0);

        deal(address(weth), address(this), weth.balanceOf(address(this)) + 1e12);
        weth.approve(address(noSwapFeeProxy), type(uint256).max);

        bytes memory data = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address,address)",
            "Lido ARM No Swap Fee",
            "ARM-ST-NO-FEE",
            operator,
            0,
            feeCollector,
            address(lpcProxy)
        );
        noSwapFeeProxy.initialize(address(noSwapFeeImpl), address(this), data);
        noSwapFeeLidoARM = LidoARM(payable(address(noSwapFeeProxy)));

        lidoARM.setPrices(BUY_PRICE, SELL_PRICE);
        noSwapFeeLidoARM.setPrices(BUY_PRICE, SELL_PRICE);

        deal(address(weth), address(lidoARM), INITIAL_ARM_BALANCE);
        deal(address(steth), address(lidoARM), INITIAL_ARM_BALANCE);
        deal(address(weth), address(noSwapFeeLidoARM), INITIAL_ARM_BALANCE);
        deal(address(steth), address(noSwapFeeLidoARM), INITIAL_ARM_BALANCE);

        deal(address(steth), upgradedUser, INITIAL_USER_BALANCE);
        deal(address(steth), noSwapFeeUser, INITIAL_USER_BALANCE);

        vm.prank(upgradedUser);
        steth.approve(address(lidoARM), type(uint256).max);

        vm.prank(noSwapFeeUser);
        steth.approve(address(noSwapFeeLidoARM), type(uint256).max);
    }

    function test_GasImpact_Baseline_SwapExactTokensForTokens_StethToWeth() public {
        uint256 baselineGas = _gasForSwapExactTokensForTokens(noSwapFeeLidoARM, noSwapFeeUser, EXACT_IN);
        emit log_named_uint("baseline swapExact stETH->WETH gas", baselineGas);
        assertEq(noSwapFeeLidoARM.feesAccrued(), 0, "baseline fee accrual");
    }

    function test_GasImpact_Upgraded_SwapExactTokensForTokens_StethToWeth() public {
        uint256 upgradedGas = _gasForSwapExactTokensForTokens(lidoARM, upgradedUser, EXACT_IN);
        emit log_named_uint("upgraded swapExact stETH->WETH gas", upgradedGas);
        assertGt(lidoARM.feesAccrued(), 0, "upgraded fee accrual");
    }

    function test_GasImpact_Baseline_SwapTokensForExactTokens_StethToWeth() public {
        uint256 baselineGas = _gasForSwapTokensForExactTokens(noSwapFeeLidoARM, noSwapFeeUser, EXACT_OUT);
        emit log_named_uint("baseline swapForExact stETH->WETH gas", baselineGas);
        assertEq(noSwapFeeLidoARM.feesAccrued(), 0, "baseline fee accrual");
    }

    function test_GasImpact_Upgraded_SwapTokensForExactTokens_StethToWeth() public {
        uint256 upgradedGas = _gasForSwapTokensForExactTokens(lidoARM, upgradedUser, EXACT_OUT);
        emit log_named_uint("upgraded swapForExact stETH->WETH gas", upgradedGas);
        assertGt(lidoARM.feesAccrued(), 0, "upgraded fee accrual");
    }

    function _gasForSwapExactTokensForTokens(LidoARM arm, address user, uint256 amountIn)
        internal
        returns (uint256 gasUsed)
    {
        vm.prank(user);
        uint256 gasBefore = gasleft();
        uint256[] memory amounts =
            arm.swapExactTokensForTokens(steth, weth, amountIn, amountIn * BUY_PRICE / 1e36, user);
        gasUsed = gasBefore - gasleft();

        assertEq(amounts[0], amountIn, "amount in");
        assertEq(amounts[1], amountIn * BUY_PRICE / 1e36, "amount out");
    }

    function _gasForSwapTokensForExactTokens(LidoARM arm, address user, uint256 amountOut)
        internal
        returns (uint256 gasUsed)
    {
        vm.prank(user);
        uint256 gasBefore = gasleft();
        uint256[] memory amounts = arm.swapTokensForExactTokens(steth, weth, amountOut, type(uint256).max, user);
        gasUsed = gasBefore - gasleft();

        assertEq(amounts[1], amountOut, "amount out");
    }
}
