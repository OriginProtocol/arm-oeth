// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

contract Fork_Concrete_LidoFixedPriceMultiLpARM_Deposit_Test_ is Fork_Shared_Test_ {
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
    
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_Deposit_SimpleCase() public setLiquidityProviderCap(address(this), 20 ether) {
        deal(address(weth), address(this), 10 ether);
        beforeData = _snapData();

        lidoARM.deposit(10 ether);

        DeltaData memory delta = noChangeDeltaData;
        delta.totalAssets = 10 ether;
        delta.totalSupply = 10 ether;
        delta.armWeth = 10 ether;
        assertData(beforeData, delta);
    }
}
