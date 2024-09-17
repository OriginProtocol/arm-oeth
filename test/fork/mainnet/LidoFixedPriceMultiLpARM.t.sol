// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";

import {IERC20} from "contracts/Interfaces.sol";
import {LidoFixedPriceMultiLpARM} from "contracts/LidoFixedPriceMultiLpARM.sol";
import {Proxy} from "contracts/Proxy.sol";

import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

contract Fork_Concrete_LidoFixedPriceMultiLpARM_Test is Fork_Shared_Test_ {
    Proxy public lidoProxy;
    LidoFixedPriceMultiLpARM public lidoARM;
    IERC20 BAD_TOKEN = IERC20(makeAddr("bad token"));
    uint256 performanceFee = 2000; // 20%
    address feeCollector = 0x000000000000000000000000000000Feec011ec1;
    AssertData beforeData;
    DeltaData noChangeDeltaData =
        DeltaData({totalAssets: 10, totalSupply: 0, totalAssetsCap: 0, armWeth: 0, armSteth: 0, feesAccrued: 0});

    struct AssertData {
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 totalAssetsCap;
        uint256 armWeth;
        uint256 armSteth;
        uint256 feesAccrued;
    }

    struct DeltaData {
        int256 totalAssets;
        int256 totalSupply;
        int256 totalAssetsCap;
        int256 armWeth;
        int256 armSteth;
        int256 feesAccrued;
    }

    function _snapData() internal view returns (AssertData memory data) {
        return AssertData({
            totalAssets: lidoARM.totalAssets(),
            totalSupply: lidoARM.totalSupply(),
            totalAssetsCap: lidoARM.totalAssetsCap(),
            armWeth: weth.balanceOf(address(lidoARM)),
            armSteth: steth.balanceOf(address(lidoARM)),
            feesAccrued: lidoARM.feesAccrued()
        });
    }

    function assertData(AssertData memory before, DeltaData memory delta) internal view {
        AssertData memory afterData = _snapData();

        assertEq(int256(afterData.totalAssets), int256(before.totalAssets) + delta.totalAssets, "totalAssets");
        assertEq(int256(afterData.totalSupply), int256(before.totalSupply) + delta.totalSupply, "totalSupply");
        assertEq(
            int256(afterData.totalAssetsCap), int256(before.totalAssetsCap) + delta.totalAssetsCap, "totalAssetsCap"
        );
        assertEq(int256(afterData.feesAccrued), int256(before.feesAccrued) + delta.feesAccrued, "feesAccrued");
        assertEq(int256(afterData.armWeth), int256(before.armWeth) + delta.armWeth, "armWeth");
        assertEq(int256(afterData.armSteth), int256(before.armSteth) + delta.armSteth, "armSteth");
    }

    // Account for stETH rounding errors.
    // See https://docs.lido.fi/guides/lido-tokens-integration-guide/#1-2-wei-corner-case
    uint256 constant ROUNDING = 2;

    function setUp() public override {
        super.setUp();

        address lidoWithdrawal = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
        LidoFixedPriceMultiLpARM lidoImpl = new LidoFixedPriceMultiLpARM(address(steth), address(weth), lidoWithdrawal);
        lidoProxy = new Proxy();

        // The deployer needs a tiny amount of WETH to initialize the ARM
        _dealWETH(address(this), 1e12);
        weth.approve(address(lidoProxy), type(uint256).max);
        steth.approve(address(lidoProxy), type(uint256).max);

        // Initialize Proxy with LidoFixedPriceMultiLpARM implementation.
        bytes memory data = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address)",
            "Lido ARM",
            "ARM-ST",
            operator,
            performanceFee,
            feeCollector
        );
        lidoProxy.initialize(address(lidoImpl), address(this), data);

        lidoARM = LidoFixedPriceMultiLpARM(payable(address(lidoProxy)));

        // set prices
        lidoARM.setPrices(992 * 1e33, 1001 * 1e33);

        lidoARM.setTotalAssetsCap(100 ether);

        // Only fuzz from this address. Big speedup on fork.
        targetSender(address(this));
    }

    function _dealStETH(address to, uint256 amount) internal {
        vm.prank(0xEB9c1CE881F0bDB25EAc4D74FccbAcF4Dd81020a);
        steth.transfer(to, amount);
    }

    function _dealWETH(address to, uint256 amount) internal {
        deal(address(weth), to, amount);
    }

    /// @dev Check initial state
    function test_initial_state() external {
        assertEq(lidoARM.name(), "Lido ARM");
        assertEq(lidoARM.symbol(), "ARM-ST");
        assertEq(lidoARM.owner(), address(this));
        assertEq(lidoARM.operator(), operator);
        assertEq(lidoARM.feeCollector(), feeCollector);
        assertEq(lidoARM.fee(), performanceFee);
        assertEq(lidoARM.lastTotalAssets(), 1e12);
        assertEq(lidoARM.feesAccrued(), 0);
        // the 20% performance fee is removed on initialization
        assertEq(lidoARM.totalAssets(), 1e12);
        assertEq(lidoARM.totalSupply(), 1e12);
        assertEq(weth.balanceOf(address(lidoARM)), 1e12);
        assertEq(lidoARM.totalAssetsCap(), 100 ether);
    }

    // whitelisted LP adds WETH liquidity to the ARM
    function test_depositAssets() external {
        lidoARM.setLiquidityProviderCap(address(this), 20 ether);

        _dealWETH(address(this), 10 ether);
        beforeData = _snapData();

        lidoARM.deposit(10 ether);

        DeltaData memory delta = noChangeDeltaData;
        delta.totalAssets = 10 ether;
        delta.totalSupply = 10 ether;
        delta.armWeth = 10 ether;
        assertData(beforeData, delta);

        // assert whitelisted LP cap was decreased
        // assert remaining liquidity in appropriate tranches increased
        // assert last total assets was set with performance fee removed
        // assert performance fee was accrued on asset increases but not the deposit
    }
    // non whitelisted LP tries to add WETH liquidity to the ARM

    function test_redeemAssets() external {
        lidoARM.setLiquidityProviderCap(address(this), 20 ether);
        _dealWETH(address(this), 10 ether);
        lidoARM.deposit(10 ether);

        lidoARM.requestRedeem(8 ether);
    }
}
