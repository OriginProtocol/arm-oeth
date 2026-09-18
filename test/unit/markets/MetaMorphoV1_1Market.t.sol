// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MetaMorphoV1_1Market, MarketParams, Market} from "contracts/markets/MetaMorphoV1_1Market.sol";

contract MockMorphoBlue {
    MarketParams internal params;
    Market internal marketState;
    uint256 public supplyShares;

    function setSupplyAssets(uint256 assets) external {
        supplyShares = assets;
        marketState = Market({
            totalSupplyAssets: uint128(assets),
            totalSupplyShares: uint128(assets - 1e6 + 1),
            totalBorrowAssets: 0,
            totalBorrowShares: 0,
            lastUpdate: uint128(block.timestamp),
            fee: 0
        });
    }

    function idToMarketParams(bytes32) external view returns (MarketParams memory) {
        return params;
    }

    function market(bytes32) external view returns (Market memory) {
        return marketState;
    }

    function position(bytes32, address) external view returns (uint256, uint128, uint128) {
        return (supplyShares, 0, 0);
    }
}

contract MockMetaMorphoV1_1 {
    address public immutable asset;
    MockMorphoBlue public immutable MORPHO;

    uint8 public constant DECIMALS_OFFSET = 0;
    uint96 public fee;
    uint256 public lastTotalAssets;
    uint256 public lostAssets;
    uint256 public realTotalAssets;
    uint256 public totalSupply;

    constructor(address _asset, MockMorphoBlue _morpho) {
        asset = _asset;
        MORPHO = _morpho;
    }

    function setAccounting(
        uint256 _totalSupply,
        uint256 _lastTotalAssets,
        uint256 _lostAssets,
        uint256 _realTotalAssets,
        uint96 _fee
    ) external {
        totalSupply = _totalSupply;
        lastTotalAssets = _lastTotalAssets;
        lostAssets = _lostAssets;
        realTotalAssets = _realTotalAssets;
        fee = _fee;
    }

    function totalAssets() external view returns (uint256) {
        uint256 newLostAssets =
            realTotalAssets < lastTotalAssets - lostAssets ? lastTotalAssets - realTotalAssets : lostAssets;
        return realTotalAssets + newLostAssets;
    }

    function withdrawQueue(uint256) external pure returns (bytes32) {
        return bytes32(uint256(1));
    }

    function withdrawQueueLength() external pure returns (uint256) {
        return 1;
    }
}

contract Unit_MetaMorphoV1_1Market_Test is Test {
    using Math for uint256;

    address internal constant ARM = address(0xA11CE);

    MockMorphoBlue internal morpho;
    MockMetaMorphoV1_1 internal vault;
    MetaMorphoV1_1Market internal wrapper;
    MockERC20 internal asset;

    function setUp() public {
        asset = new MockERC20("Wrapped Ether", "WETH", 18);
        morpho = new MockMorphoBlue();
        vault = new MockMetaMorphoV1_1(address(asset), morpho);
        wrapper = new MetaMorphoV1_1Market(ARM, address(vault));
    }

    function test_ConvertToAssets_NoLoss() public {
        morpho.setSupplyAssets(100 ether);
        vault.setAccounting(100 ether, 100 ether, 0, 100 ether, 0);

        assertEq(wrapper.convertToAssets(100 ether), 100 ether, "assets without loss");
    }

    function test_ConvertToAssets_IncludesIdleAssets() public {
        morpho.setSupplyAssets(60 ether);
        asset.mint(address(vault), 40 ether);
        vault.setAccounting(100 ether, 100 ether, 0, 100 ether, 0);

        assertEq(wrapper.convertToAssets(100 ether), 100 ether, "assets including idle balance");
    }

    function test_ConvertToAssets_RecordedLoss() public {
        morpho.setSupplyAssets(60 ether);
        vault.setAccounting(100 ether, 100 ether, 40 ether, 60 ether, 0);

        assertEq(wrapper.convertToAssets(100 ether), 60 ether, "assets after recorded loss");
    }

    function test_ConvertToAssets_NewlyDetectedLoss() public {
        morpho.setSupplyAssets(60 ether);
        // The liquidation has reduced real assets, but no MetaMorpho state-changing call has
        // persisted the corresponding 40 WETH in lostAssets yet.
        vault.setAccounting(100 ether, 100 ether, 0, 60 ether, 0);

        assertEq(vault.lostAssets(), 0, "recorded lost assets");
        assertEq(wrapper.convertToAssets(100 ether), 60 ether, "assets after detected loss");
    }

    function test_ConvertToAssets_IncludesPendingFeeShares() public {
        morpho.setSupplyAssets(110 ether);
        vault.setAccounting(100 ether, 100 ether, 0, 110 ether, 0.1 ether); // 0.1e18 = 10% fee

        uint256 feeAssets = 1 ether;
        uint256 feeShares = feeAssets.mulDiv(100 ether + 1, 110 ether - feeAssets + 1);
        uint256 expectedAssets = uint256(100 ether).mulDiv(110 ether + 1, 100 ether + feeShares + 1);

        assertEq(wrapper.convertToAssets(100 ether), expectedAssets, "assets after pending fees");
    }
}
