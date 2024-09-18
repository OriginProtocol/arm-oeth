// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
/*
import {Test, console2} from "forge-std/Test.sol";

import {IERC20} from "contracts/Interfaces.sol";
import {LidoMultiPriceMultiLpARM} from "contracts/LidoMultiPriceMultiLpARM.sol";
import {Proxy} from "contracts/Proxy.sol";

import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

contract Fork_Concrete_LidoMultiPriceMultiLpARM_Test is Fork_Shared_Test_ {
    Proxy public lidoProxy;
    LidoMultiPriceMultiLpARM public lidoARM;
    IERC20 BAD_TOKEN = IERC20(makeAddr("bad token"));
    uint256 performanceFee = 2000; // 20%
    address feeCollector = 0x000000000000000000000000000000Feec011ec1;
    AssertData beforeData;
    DeltaData noChangeDeltaData = DeltaData({
        totalAssets: 10,
        totalSupply: 0,
        totalAssetsCap: 0,
        armWeth: 0,
        armSteth: 0,
        feesAccrued: 0,
        tranchesDiscounts: [int16(0), 0, 0, 0, 0],
        tranchesAllocations: [int256(0), 0, 0, 0, 0],
        tranchesRemaining: [int256(0), 0, 0, 0, 0]
    });

    struct AssertData {
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 totalAssetsCap;
        uint256 armWeth;
        uint256 armSteth;
        uint256 feesAccrued;
        uint16[5] tranchesDiscounts;
        uint256[5] tranchesAllocations;
        uint256[5] tranchesRemaining;
    }

    struct DeltaData {
        int256 totalAssets;
        int256 totalSupply;
        int256 totalAssetsCap;
        int256 armWeth;
        int256 armSteth;
        int256 feesAccrued;
        int16[5] tranchesDiscounts;
        int256[5] tranchesAllocations;
        int256[5] tranchesRemaining;
    }

    function _snapData() internal view returns (AssertData memory data) {
        return AssertData({
            totalAssets: lidoARM.totalAssets(),
            totalSupply: lidoARM.totalSupply(),
            totalAssetsCap: lidoARM.totalAssetsCap(),
            armWeth: weth.balanceOf(address(lidoARM)),
            armSteth: steth.balanceOf(address(lidoARM)),
            feesAccrued: lidoARM.feesAccrued(),
            tranchesDiscounts: lidoARM.getTrancheDiscounts(),
            tranchesAllocations: lidoARM.getTrancheAllocations(),
            tranchesRemaining: lidoARM.getTrancheRemaining()
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
        // for (uint256 i = 0; i < 5; i++) {
        //     assertEq(afterData.tranchesDiscounts[i], before.tranchesDiscounts[i] + delta.tranchesDiscounts[i]);
        //     assertEq(afterData.tranchesAllocations[i], before.tranchesAllocations[i] + delta.tranchesAllocations[i]);
        //     assertEq(afterData.tranchesRemaining[i], before.tranchesRemaining[i] + delta.tranchesRemaining[i]);
        // }
    }

    // Account for stETH rounding errors.
    // See https://docs.lido.fi/guides/lido-tokens-integration-guide/#1-2-wei-corner-case
    uint256 constant ROUNDING = 2;

    function setUp() public override {
        super.setUp();

        address lidoWithdrawal = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
        LidoMultiPriceMultiLpARM lidoImpl = new LidoMultiPriceMultiLpARM(address(steth), address(weth), lidoWithdrawal);
        lidoProxy = new Proxy();

        // The deployer needs a tiny amount of WETH to initialize the ARM
        _dealWETH(address(this), 1e12);
        weth.approve(address(lidoProxy), type(uint256).max);
        steth.approve(address(lidoProxy), type(uint256).max);

        // Initialize Proxy with LidoMultiPriceMultiLpARM implementation.
        bytes memory data = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address)",
            "Lido ARM",
            "ARM-ST",
            operator,
            performanceFee,
            feeCollector
        );
        lidoProxy.initialize(address(lidoImpl), address(this), data);

        lidoARM = LidoMultiPriceMultiLpARM(payable(address(lidoProxy)));

        // Set the tranche discounts for each tranche
        // 8 basis point discount (0.08%) would be 800 with a price of 0.9992
        lidoARM.setTrancheDiscounts([uint16(200), 375, 800, 1400, 1800]);
        lidoARM.setTrancheAllocations([uint256(80 ether), 50 ether, 30 ether, 20 ether, 10 ether]);

        lidoARM.setTotalAssetsCap(100 ether);

        address[] memory liquidityProviders = new address[](1);
        liquidityProviders[0] = address(this);
        lidoARM.setLiquidityProviderCaps(liquidityProviders, 20 ether);

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
    function test_initial_state() external view {
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

    /// @dev ARM owner sets valid trance discounts ranging from 1 to MAX_DISCOUNT
    function test_setValidTrancheDiscounts() external {
        lidoARM.setTrancheDiscounts([uint16(1), 20, 300, 9999, 65535]);
        uint16[5] memory discounts = lidoARM.getTrancheDiscounts();
        assertEq(discounts[0], 1);
        assertEq(discounts[1], 20);
        assertEq(discounts[2], 300);
        assertEq(discounts[3], 9999);
        assertEq(discounts[4], 65535);
    }
    // Revert when a tranche discount is zero
    // Revert when a tranche discount is greater than the MAX_DISCOUNT
    // Revert when non owner tries to set tranche discounts

    // whitelisted LP adds WETH liquidity to the ARM
    function test_depositAssets() external {
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
        _dealWETH(address(this), 10 ether);
        lidoARM.deposit(10 ether);

        lidoARM.requestRedeem(8 ether);
    }

    // with enough liquidity in all tranches
    //// swap stETH to WETH using just the first tranche
    //// swap stETH to WETH using the first two tranches
    //// swap stETH to WETH using all five tranches
    //// fail to swap stETH to WETH with a swap larger than the available liquidity
    // with all liquidity in the first tranche used
    //// swap stETH to WETH using just the second tranche
    //// swap stETH to WETH using the second and third tranches
    //// swap stETH to WETH using the remaining four tranches
    //// fail to swap stETH to WETH with a swap larger than the available liquidity
    // with only liquidity in the fifth tranche
    //// swap stETH to WETH using just the fifth tranche
}
*/