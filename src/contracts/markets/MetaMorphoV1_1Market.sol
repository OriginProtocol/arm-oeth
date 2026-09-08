// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.36;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Abstract4626MarketWrapper} from "./Abstract4626MarketWrapper.sol";

struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

interface IMorphoBlue {
    function idToMarketParams(bytes32 id) external view returns (MarketParams memory);
    function market(bytes32 id) external view returns (Market memory);
    function position(bytes32 id, address user)
        external
        view
        returns (uint256 supplyShares, uint128 borrowShares, uint128 collateral);
}

interface IMorphoIrm {
    function borrowRateView(MarketParams memory marketParams, Market memory market) external view returns (uint256);
}

interface IMetaMorphoV1_1 {
    function DECIMALS_OFFSET() external view returns (uint8);
    function MORPHO() external view returns (IMorphoBlue);
    function fee() external view returns (uint96);
    function lastTotalAssets() external view returns (uint256);
    function lostAssets() external view returns (uint256);
    function withdrawQueue(uint256 index) external view returns (bytes32);
    function withdrawQueueLength() external view returns (uint256);
}

/**
 * @title MetaMorpho V1.1 lending market wrapper
 * @notice Values MetaMorpho V1.1 positions without counting lost assets while retaining Morpho rewards support.
 * @author Origin Protocol Inc
 */
contract MetaMorphoV1_1Market is Abstract4626MarketWrapper {
    using Math for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant MORPHO_VIRTUAL_SHARES = 1e6;

    /// @notice The address of the Morpho Token contract.
    IERC20 public constant MORPHO_TOKEN = IERC20(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);

    constructor(address _arm, address _market) Abstract4626MarketWrapper(_arm, _market) {}

    /// @notice Values MetaMorpho V1.1 shares using assets that actually exist in Morpho Blue.
    /// @dev MetaMorpho includes `lostAssets` in `totalAssets()`, keeping its ERC-4626 share price
    /// unchanged after bad debt. Reproducing its conversion with real assets makes the ARM recognize
    /// the loss while retaining the vault's treatment of virtual shares and pending performance fees.
    /// The stored `lostAssets` value is not subtracted directly because it can lag a newly detected
    /// loss until MetaMorpho executes a state-changing accrual. Reading the underlying Morpho Blue
    /// positions recognizes both persisted and newly detected losses. The explicit `lostAssets()`
    /// call below instead verifies that the configured vault supports the MetaMorpho V1.1 interface.
    function convertToAssets(uint256 shares) external view override returns (uint256 assets) {
        IMetaMorphoV1_1 metaMorpho = IMetaMorphoV1_1(market);

        // Explicitly require the V1.1 interface. V1.0 vaults are not supported by this wrapper.
        metaMorpho.lostAssets();

        uint256 realTotalAssets = _realTotalAssets(metaMorpho);
        uint256 reportedTotalAssets = IERC4626(market).totalAssets();
        uint256 totalSupply = _totalSupplyWithPendingFees(metaMorpho, reportedTotalAssets);

        assets = shares.mulDiv(realTotalAssets + 1, totalSupply + 10 ** metaMorpho.DECIMALS_OFFSET());
    }

    /// @notice Calculates the MetaMorpho vault assets that are economically attributable to its share holders.
    /// @dev Starts with unallocated assets held by the vault, then converts the vault's supply shares in every
    /// market in its withdrawal queue using the current expected Morpho Blue balances. Unlike MetaMorpho V1.1
    /// `totalAssets()`, this sum does not add `lostAssets`, so bad debt reduces the returned value even before the
    /// loss is persisted by MetaMorpho.
    /// @param metaMorpho The MetaMorpho V1.1 vault whose real assets are being calculated.
    /// @return realTotalAssets The vault's idle assets plus the recoverable value of its Morpho Blue positions.
    function _realTotalAssets(IMetaMorphoV1_1 metaMorpho) internal view returns (uint256 realTotalAssets) {
        realTotalAssets = IERC20(asset).balanceOf(market);

        IMorphoBlue morpho = metaMorpho.MORPHO();
        uint256 queueLength = metaMorpho.withdrawQueueLength();
        for (uint256 i; i < queueLength; ++i) {
            bytes32 marketId = metaMorpho.withdrawQueue(i);
            MarketParams memory marketParams = morpho.idToMarketParams(marketId);
            Market memory marketState = _expectedMarketState(morpho.market(marketId), marketParams);
            (uint256 supplyShares,,) = morpho.position(marketId, market);
            realTotalAssets += supplyShares.mulDiv(
                uint256(marketState.totalSupplyAssets) + 1,
                uint256(marketState.totalSupplyShares) + MORPHO_VIRTUAL_SHARES
            );
        }
    }

    /// @notice Accrues a stored Morpho Blue market state in memory to the current block timestamp.
    /// @dev Reproduces the supply-side calculations in `MorphoBalancesLib.expectedMarketBalances`. It compounds the
    /// current borrow rate with Morpho's three-term Taylor approximation, adds the resulting interest to supplied and
    /// borrowed assets, and dilutes suppliers by the protocol fee shares. This is view-only and does not modify Morpho.
    /// @param marketState The stored Morpho Blue market balances and fee configuration.
    /// @param marketParams The market parameters, including the interest-rate model used to obtain the current rate.
    /// @return The expected market state after accruing interest and protocol fees through the current timestamp.
    function _expectedMarketState(Market memory marketState, MarketParams memory marketParams)
        internal
        view
        returns (Market memory)
    {
        uint256 elapsed = block.timestamp - marketState.lastUpdate;
        if (elapsed == 0 || marketState.totalBorrowAssets == 0 || marketParams.irm == address(0)) return marketState;

        uint256 borrowRate = IMorphoIrm(marketParams.irm).borrowRateView(marketParams, marketState);
        uint256 firstTerm = borrowRate * elapsed;
        uint256 secondTerm = firstTerm.mulDiv(firstTerm, 2 * WAD);
        uint256 thirdTerm = secondTerm.mulDiv(firstTerm, 3 * WAD);
        uint256 interest = uint256(marketState.totalBorrowAssets).mulDiv(firstTerm + secondTerm + thirdTerm, WAD);

        marketState.totalBorrowAssets += uint128(interest);
        marketState.totalSupplyAssets += uint128(interest);

        if (marketState.fee != 0) {
            uint256 feeAssets = interest.mulDiv(marketState.fee, WAD);
            uint256 feeShares = feeAssets.mulDiv(
                uint256(marketState.totalSupplyShares) + MORPHO_VIRTUAL_SHARES,
                uint256(marketState.totalSupplyAssets) - feeAssets + 1
            );
            marketState.totalSupplyShares += uint128(feeShares);
        }

        return marketState;
    }

    /// @notice Calculates the MetaMorpho share supply after accounting for unminted performance-fee shares.
    /// @dev MetaMorpho mints performance-fee shares when it accrues state. Until then, `totalSupply()` excludes those
    /// shares even though its conversion functions price them in. This reproduces the pending fee-share calculation
    /// so the ARM's conversion has the same dilution. The reported MetaMorpho assets are intentionally used for fee
    /// accounting, while `_realTotalAssets` is used separately to exclude phantom `lostAssets` from the numerator.
    /// @param metaMorpho The MetaMorpho V1.1 vault whose effective share supply is being calculated.
    /// @param reportedTotalAssets The vault's current `totalAssets()`, including MetaMorpho's `lostAssets` treatment.
    /// @return totalSupply The stored share supply plus any performance-fee shares pending minting.
    function _totalSupplyWithPendingFees(IMetaMorphoV1_1 metaMorpho, uint256 reportedTotalAssets)
        internal
        view
        returns (uint256 totalSupply)
    {
        totalSupply = IERC20(market).totalSupply();
        uint256 lastTotalAssets = metaMorpho.lastTotalAssets();
        uint256 fee = metaMorpho.fee();
        if (reportedTotalAssets > lastTotalAssets && fee != 0) {
            uint256 feeAssets = (reportedTotalAssets - lastTotalAssets).mulDiv(fee, WAD);
            uint256 virtualShares = 10 ** metaMorpho.DECIMALS_OFFSET();
            uint256 feeShares = feeAssets.mulDiv(totalSupply + virtualShares, reportedTotalAssets - feeAssets + 1);
            totalSupply += feeShares;
        }
    }

    /// @notice Claim all Morpho tokens and send them to the Harvester.
    function _collectRewards() internal override returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(MORPHO_TOKEN);
        amounts[0] = MORPHO_TOKEN.balanceOf(address(this));

        if (amounts[0] > 0) {
            MORPHO_TOKEN.transfer(harvester, amounts[0]);
        }

        emit CollectedRewards(tokens, amounts);

        return (tokens, amounts);
    }
}
