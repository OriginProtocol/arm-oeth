// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IERC20} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";
import {LegacyLidoARMForGasTest} from "test/mocks/LegacyLidoARMForGasTest.sol";

interface IBenchmarkARM {
    function swapExactTokensForTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external returns (uint256[] memory amounts);
    function feesAccrued() external view returns (uint256);
}

abstract contract Fork_Shared_LidoARM_SwapGasImpact_Test is Fork_Shared_Test_ {
    uint256 internal constant INITIAL_ARM_BALANCE = 1_000 ether;
    uint256 internal constant BUY_PRICE = 0.9995e36;
    uint256 internal constant SELL_PRICE = 1.001e36;
    uint256 internal constant EXACT_IN = 100 ether;
    uint256 internal constant EXACT_OUT = 99.95 ether;

    Proxy internal legacyProxy;
    LegacyLidoARMForGasTest internal legacyLidoARM;

    address internal legacyUser;
    address internal upgradedUser;

    function setUp() public virtual override {
        super.setUp();

        legacyUser = makeAddr("legacyUser");
        upgradedUser = makeAddr("upgradedUser");

        legacyProxy = new Proxy();
        LegacyLidoARMForGasTest legacyImpl = new LegacyLidoARMForGasTest(address(steth), address(weth));

        deal(address(weth), address(this), weth.balanceOf(address(this)) + 1e12);
        weth.approve(address(legacyProxy), type(uint256).max);

        bytes memory data = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address,address)",
            "Legacy Lido ARM",
            "ARM-ST-LEGACY",
            operator,
            2000,
            feeCollector,
            address(lpcProxy)
        );
        legacyProxy.initialize(address(legacyImpl), address(this), data);
        legacyLidoARM = LegacyLidoARMForGasTest(payable(address(legacyProxy)));

        legacyLidoARM.setPrices(BUY_PRICE, SELL_PRICE);
        lidoARM.setPrices(BUY_PRICE, SELL_PRICE);

        deal(address(steth), legacyUser, EXACT_IN * 4);
        deal(address(steth), upgradedUser, EXACT_IN * 4);

        vm.prank(legacyUser);
        steth.approve(address(legacyLidoARM), type(uint256).max);

        vm.prank(upgradedUser);
        steth.approve(address(lidoARM), type(uint256).max);

        _prepareScenario();
    }

    function _prepareScenario() internal virtual;

    function _gasForSwapExactTokensForTokens(IBenchmarkARM arm, address user) internal returns (uint256 gasUsed) {
        deal(address(steth), user, steth.balanceOf(user) + EXACT_IN);

        vm.prank(user);
        uint256 gasBefore = gasleft();
        uint256[] memory amounts =
            arm.swapExactTokensForTokens(steth, weth, EXACT_IN, EXACT_IN * BUY_PRICE / 1e36, user);
        gasUsed = gasBefore - gasleft();

        assertEq(amounts[0], EXACT_IN, "amount in");
        assertEq(amounts[1], EXACT_IN * BUY_PRICE / 1e36, "amount out");
    }

    function _setArmBalances(address arm, uint256 wethBalance, uint256 stethBalance) internal {
        deal(address(weth), arm, 0);
        deal(address(steth), arm, 0);
        deal(address(weth), arm, wethBalance);
        deal(address(steth), arm, stethBalance);
    }

    function _legacyAvailableAssets() internal pure returns (int128) {
        return SafeCast.toInt128(SafeCast.toInt256(INITIAL_ARM_BALANCE * 2));
    }

    function _setPackedFeesAccrued(address arm, uint128 value) internal {
        bytes32 slot = vm.load(arm, bytes32(_FEE_STORAGE_SLOT));
        uint256 preservedFee = uint256(slot) & 0xFFFF;
        uint256 encodedValue = uint256(value) << 16;
        vm.store(arm, bytes32(_FEE_STORAGE_SLOT), bytes32(preservedFee | encodedValue));
    }
}

contract Fork_Concrete_LegacyLidoARM_AfterCollect_SwapGasImpact_Test is Fork_Shared_LidoARM_SwapGasImpact_Test {
    function _prepareScenario() internal override {
        _setArmBalances(address(legacyLidoARM), INITIAL_ARM_BALANCE, INITIAL_ARM_BALANCE);
        legacyLidoARM.setLastAvailableAssetsForGasTest(_legacyAvailableAssets());
    }

    function test_GasImpact() public {
        assertEq(IBenchmarkARM(address(legacyLidoARM)).feesAccrued(), 0, "legacy fees should be collected");

        uint256 gasUsed = _gasForSwapExactTokensForTokens(IBenchmarkARM(address(legacyLidoARM)), legacyUser);
        emit log_named_uint("legacy performance fee after collect swapExact stETH->WETH gas", gasUsed);
    }
}

contract Fork_Concrete_LegacyLidoARM_AfterAnotherSwap_SwapGasImpact_Test is Fork_Shared_LidoARM_SwapGasImpact_Test {
    function _prepareScenario() internal override {
        _setArmBalances(address(legacyLidoARM), INITIAL_ARM_BALANCE - EXACT_OUT, INITIAL_ARM_BALANCE + EXACT_IN);
        legacyLidoARM.setLastAvailableAssetsForGasTest(_legacyAvailableAssets());
    }

    function test_GasImpact() public {
        assertGt(IBenchmarkARM(address(legacyLidoARM)).feesAccrued(), 0, "legacy swap should create performance fees");

        uint256 gasUsed = _gasForSwapExactTokensForTokens(IBenchmarkARM(address(legacyLidoARM)), legacyUser);
        emit log_named_uint("legacy performance fee after another swap swapExact stETH->WETH gas", gasUsed);
    }
}

contract Fork_Concrete_NewLidoARM_AfterCollect_SwapGasImpact_Test is Fork_Shared_LidoARM_SwapGasImpact_Test {
    function _prepareScenario() internal override {
        _setArmBalances(address(lidoARM), INITIAL_ARM_BALANCE, INITIAL_ARM_BALANCE);
        _setPackedFeesAccrued(address(lidoARM), 1);
    }

    function test_GasImpact() public {
        assertEq(IBenchmarkARM(address(lidoARM)).feesAccrued(), 1, "new swap fee should reset to sentinel");

        uint256 gasUsed = _gasForSwapExactTokensForTokens(IBenchmarkARM(address(lidoARM)), upgradedUser);
        emit log_named_uint("new swap fee after collect swapExact stETH->WETH gas", gasUsed);
    }
}

contract Fork_Concrete_NewLidoARM_AfterAnotherSwap_SwapGasImpact_Test is Fork_Shared_LidoARM_SwapGasImpact_Test {
    function _prepareScenario() internal override {
        _setArmBalances(address(lidoARM), INITIAL_ARM_BALANCE - EXACT_OUT, INITIAL_ARM_BALANCE + EXACT_IN);
        _setPackedFeesAccrued(
            address(lidoARM), uint128((EXACT_IN - EXACT_OUT) * lidoARM.fee() / lidoARM.FEE_SCALE() + 1)
        );
    }

    function test_GasImpact() public {
        assertGt(IBenchmarkARM(address(lidoARM)).feesAccrued(), 1, "new swap should leave accrued swap fees");

        uint256 gasUsed = _gasForSwapExactTokensForTokens(IBenchmarkARM(address(lidoARM)), upgradedUser);
        emit log_named_uint("new swap fee after another swap swapExact stETH->WETH gas", gasUsed);
    }
}
