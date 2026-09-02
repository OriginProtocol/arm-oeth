// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {Proxy} from "contracts/Proxy.sol";
import {
    IMorphoBlue,
    IMorphoIrm,
    MorphoBlueMarket,
    MorphoMarketId,
    MorphoMarketParams,
    MorphoMarketState,
    MorphoPosition
} from "contracts/markets/MorphoBlueMarket.sol";

contract MockMorphoIrm is IMorphoIrm {
    uint256 public rate;

    function setRate(uint256 newRate) external {
        rate = newRate;
    }

    function borrowRateView(MorphoMarketParams memory, MorphoMarketState memory) external view returns (uint256) {
        return rate;
    }
}

contract MockMorphoBlue is IMorphoBlue {
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    mapping(MorphoMarketId => MorphoMarketState) internal states;
    mapping(MorphoMarketId => mapping(address => MorphoPosition)) internal positions;

    function createMarket(MorphoMarketParams memory params) external {
        states[_id(params)].lastUpdate = uint128(block.timestamp);
    }

    function setBorrowAssets(MorphoMarketParams memory params, uint128 assets) external {
        states[_id(params)].totalBorrowAssets = assets;
    }

    function setTotals(
        MorphoMarketParams memory params,
        uint128 supplyAssets,
        uint128 supplyShares,
        uint128 borrowAssets,
        uint128 fee
    ) external {
        MorphoMarketState storage state = states[_id(params)];
        state.totalSupplyAssets = supplyAssets;
        state.totalSupplyShares = supplyShares;
        state.totalBorrowAssets = borrowAssets;
        state.lastUpdate = uint128(block.timestamp);
        state.fee = fee;
    }

    function supply(MorphoMarketParams memory params, uint256 assets, uint256, address onBehalf, bytes memory)
        external
        returns (uint256 assetsSupplied, uint256 sharesSupplied)
    {
        MorphoMarketId id = _id(params);
        _accrue(params);
        MorphoMarketState storage state = states[id];
        sharesSupplied = assets * (uint256(state.totalSupplyShares) + VIRTUAL_SHARES)
            / (uint256(state.totalSupplyAssets) + VIRTUAL_ASSETS);
        state.totalSupplyAssets += uint128(assets);
        state.totalSupplyShares += uint128(sharesSupplied);
        positions[id][onBehalf].supplyShares += sharesSupplied;
        MockERC20(params.loanToken).transferFrom(msg.sender, address(this), assets);
        return (assets, sharesSupplied);
    }

    function withdraw(
        MorphoMarketParams memory params,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn) {
        MorphoMarketId id = _id(params);
        _accrue(params);
        MorphoMarketState storage state = states[id];

        if (shares == 0) {
            shares = _divUp(
                assets * (uint256(state.totalSupplyShares) + VIRTUAL_SHARES),
                uint256(state.totalSupplyAssets) + VIRTUAL_ASSETS
            );
        } else {
            assets = shares * (uint256(state.totalSupplyAssets) + VIRTUAL_ASSETS)
                / (uint256(state.totalSupplyShares) + VIRTUAL_SHARES);
        }

        require(assets <= uint256(state.totalSupplyAssets) - uint256(state.totalBorrowAssets), "insufficient liquidity");
        positions[id][onBehalf].supplyShares -= shares;
        state.totalSupplyAssets -= uint128(assets);
        state.totalSupplyShares -= uint128(shares);
        MockERC20(params.loanToken).transfer(receiver, assets);
        return (assets, shares);
    }

    function accrueInterest(MorphoMarketParams memory params) external {
        _accrue(params);
    }

    function position(MorphoMarketId id, address user) external view returns (MorphoPosition memory) {
        return positions[id][user];
    }

    function market(MorphoMarketId id) external view returns (MorphoMarketState memory) {
        return states[id];
    }

    function _accrue(MorphoMarketParams memory params) internal {
        MorphoMarketState storage state = states[_id(params)];
        uint256 elapsed = block.timestamp - state.lastUpdate;
        if (elapsed == 0 || state.totalBorrowAssets == 0) return;

        uint256 rate = IMorphoIrm(params.irm).borrowRateView(params, state);
        uint256 firstTerm = rate * elapsed;
        uint256 secondTerm = firstTerm * firstTerm / (2e18);
        uint256 thirdTerm = secondTerm * firstTerm / (3e18);
        uint256 interest = uint256(state.totalBorrowAssets) * (firstTerm + secondTerm + thirdTerm) / 1e18;
        state.totalBorrowAssets += uint128(interest);
        state.totalSupplyAssets += uint128(interest);
        state.lastUpdate = uint128(block.timestamp);
    }

    function _id(MorphoMarketParams memory params) internal pure returns (MorphoMarketId) {
        return MorphoMarketId.wrap(keccak256(abi.encode(params)));
    }

    function _divUp(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        return (numerator + denominator - 1) / denominator;
    }
}

contract Unit_MorphoBlueMarket_Test is Test {
    MockERC20 internal usdc;
    MockMorphoIrm internal irm;
    MockMorphoBlue internal morpho;
    MorphoBlueMarket internal wrapper;
    MorphoMarketParams internal params;

    address internal governor = makeAddr("governor");
    address internal harvester = makeAddr("harvester");
    address internal distributor = makeAddr("distributor");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        irm = new MockMorphoIrm();
        morpho = new MockMorphoBlue();

        params = MorphoMarketParams({
            loanToken: address(usdc),
            collateralToken: makeAddr("collateral"),
            oracle: makeAddr("oracle"),
            irm: address(irm),
            lltv: 0.86e18
        });
        morpho.createMarket(params);

        wrapper = _deployWrapper(params);
        usdc.approve(address(wrapper), type(uint256).max);
    }

    function test_InitializeStoresOneMarketConfiguration() external view {
        assertEq(wrapper.arm(), address(this));
        assertEq(wrapper.asset(), address(usdc));
        assertEq(MorphoMarketId.unwrap(wrapper.marketId()), keccak256(abi.encode(params)));
        (address loanToken, address collateralToken, address oracle, address marketIrm, uint256 lltv) =
            wrapper.marketParams();
        assertEq(loanToken, params.loanToken);
        assertEq(collateralToken, params.collateralToken);
        assertEq(oracle, params.oracle);
        assertEq(marketIrm, params.irm);
        assertEq(lltv, params.lltv);
        assertEq(address(wrapper.morpho()), address(morpho));
        assertEq(wrapper.harvester(), harvester);
        assertEq(address(wrapper.merkleDistributor()), distributor);
    }

    function test_SeparateImplementationsSupportImmutableMarketConfigurations() external {
        MorphoMarketParams memory secondParams = params;
        secondParams.collateralToken = makeAddr("second collateral");
        morpho.createMarket(secondParams);

        MorphoBlueMarket secondWrapper = _deployWrapper(secondParams);
        assertNotEq(
            Proxy(payable(address(wrapper))).implementation(),
            Proxy(payable(address(secondWrapper))).implementation(),
            "implementations"
        );
        assertNotEq(
            MorphoMarketId.unwrap(wrapper.marketId()), MorphoMarketId.unwrap(secondWrapper.marketId()), "market ids"
        );
    }

    function test_DepositAndRedeemFullPosition() external {
        usdc.mint(address(this), 1_000e6);
        uint256 shares = wrapper.deposit(1_000e6, address(this));

        assertGt(shares, 0);
        assertEq(wrapper.balanceOf(address(this)), shares);
        assertApproxEqAbs(wrapper.convertToAssets(shares), 1_000e6, 1);

        uint256 assets = wrapper.redeem(shares, address(this), address(this));
        assertApproxEqAbs(assets, 1_000e6, 1);
        assertEq(wrapper.balanceOf(address(this)), 0);
    }

    function test_ViewsIncludePendingInterestAndProtocolFeeDilution() external {
        usdc.mint(address(this), 1_000e6);
        uint256 shares = wrapper.deposit(1_000e6, address(this));

        // Seed borrowing without removing mock liquidity. 10% simple first-order interest over the warp.
        morpho.setTotals(params, 1_000e6, uint128(shares), 500e6, 0.1e18);
        irm.setRate(1e17 / 100);
        vm.warp(block.timestamp + 100);

        assertGt(wrapper.convertToAssets(shares), 1_000e6);
        // A 10% protocol fee dilutes the wrapper relative to a fee-free projection.
        uint256 netAssets = wrapper.convertToAssets(shares);
        morpho.setTotals(params, 1_000e6, uint128(shares), 500e6, 0);
        vm.warp(block.timestamp + 100);
        uint256 grossAssets = wrapper.convertToAssets(shares);
        assertLt(netAssets, grossAssets);
    }

    function test_MaxWithdrawLimitedByMarketLiquidity() external {
        usdc.mint(address(this), 1_000e6);
        wrapper.deposit(1_000e6, address(this));
        morpho.setBorrowAssets(params, 800e6);

        assertApproxEqAbs(wrapper.maxWithdraw(address(this)), 200e6, 1);
        assertLt(wrapper.maxRedeem(address(this)), wrapper.balanceOf(address(this)));
    }

    function test_RevertWhen_NonArmMovesPosition() external {
        vm.startPrank(attacker);
        vm.expectRevert(MorphoBlueMarket.OnlyARM.selector);
        wrapper.deposit(1, attacker);
        vm.expectRevert(MorphoBlueMarket.OnlyARM.selector);
        wrapper.withdraw(1, attacker, attacker);
        vm.expectRevert(MorphoBlueMarket.OnlyARM.selector);
        wrapper.redeem(1, attacker, attacker);
        vm.stopPrank();
    }

    function test_CollectRewardsRoutesAssetToArmAndOtherTokensToHarvester() external {
        MockERC20 rewardToken = new MockERC20("Reward", "RWD", 18);
        usdc.mint(address(wrapper), 100e6);
        rewardToken.mint(address(wrapper), 2 ether);

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(rewardToken);

        vm.prank(harvester);
        uint256[] memory amounts = wrapper.collectRewards(tokens);

        assertEq(amounts[0], 100e6);
        assertEq(amounts[1], 2 ether);
        assertEq(usdc.balanceOf(address(this)), 100e6, "USDC returned to ARM");
        assertEq(rewardToken.balanceOf(harvester), 2 ether, "other reward sent to harvester");
        assertEq(usdc.balanceOf(address(wrapper)), 0);
        assertEq(rewardToken.balanceOf(address(wrapper)), 0);
    }

    function test_RevertWhen_NonHarvesterCollectsRewards() external {
        vm.prank(attacker);
        vm.expectRevert(MorphoBlueMarket.OnlyHarvester.selector);
        wrapper.collectRewards(new address[](0));
    }

    function test_RevertWhen_TransferTokensRecipientInvalid() external {
        vm.prank(governor);
        vm.expectRevert(MorphoBlueMarket.InvalidRecipient.selector);
        wrapper.transferTokens(address(usdc), attacker, 1);
    }

    function test_RevertWhen_InitializingUnknownMarket() external {
        MorphoMarketParams memory unknownParams = params;
        unknownParams.collateralToken = makeAddr("unknown collateral");

        vm.expectRevert(MorphoBlueMarket.InvalidMarket.selector);
        new MorphoBlueMarket(address(morpho), address(this), unknownParams);
    }

    function _deployWrapper(MorphoMarketParams memory marketParams) internal returns (MorphoBlueMarket deployed) {
        MorphoBlueMarket implementation = new MorphoBlueMarket(address(morpho), address(this), marketParams);
        Proxy proxy = new Proxy();
        proxy.initialize(
            address(implementation), governor, abi.encodeCall(MorphoBlueMarket.initialize, (harvester, distributor))
        );
        return MorphoBlueMarket(address(proxy));
    }
}
