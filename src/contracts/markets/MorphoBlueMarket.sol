// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "../Ownable.sol";
import {IDistributor} from "../Interfaces.sol";

type MorphoMarketId is bytes32;

struct MorphoMarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

struct MorphoPosition {
    uint256 supplyShares;
    uint128 borrowShares;
    uint128 collateral;
}

struct MorphoMarketState {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

interface IMorphoBlue {
    function supply(
        MorphoMarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) external returns (uint256 assetsSupplied, uint256 sharesSupplied);

    function withdraw(
        MorphoMarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn);

    function accrueInterest(MorphoMarketParams memory marketParams) external;
    function position(MorphoMarketId id, address user) external view returns (MorphoPosition memory);
    function market(MorphoMarketId id) external view returns (MorphoMarketState memory);
}

interface IMorphoIrm {
    function borrowRateView(MorphoMarketParams memory marketParams, MorphoMarketState memory market)
        external
        view
        returns (uint256);
}

/**
 * @title ERC-4626-compatible wrapper for one Morpho Blue market.
 * @notice Each implementation is constructed with one immutable Morpho market configuration.
 * @dev The wrapper deliberately has no ERC-20 share token. Its ERC-4626-style balance is the
 *      Morpho supply-share position owned by this contract and exposed only to the linked ARM.
 * @author Origin Protocol Inc
 */
contract MorphoBlueMarket is Initializable, Ownable {
    using Math for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    IMorphoBlue public immutable morpho;
    address public immutable arm;
    address public immutable asset;
    MorphoMarketId public immutable marketId;

    address private immutable _collateralToken;
    address private immutable _oracle;
    address private immutable _irm;
    uint256 private immutable _lltv;

    address public harvester;
    IDistributor public merkleDistributor;

    uint256[50] private _gap;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event HarvesterUpdated(address harvester);
    event MerkleDistributorUpdated(address merkleDistributor);
    event CollectedRewards(address[] tokens, uint256[] amounts);

    error OnlyARM(); // 0x1628bf2a
    error OnlyHarvester(); // 0xbc4583db
    error InvalidARM(); // 0xc0a9bda4
    error InvalidMarket(); // 0x9db8d5b1
    error InvalidHarvester(); // 0xee486cb6
    error InvalidMerkleDistributor(); // 0xfff74fbb
    error InvalidRecipient(); // 0x9c8d2cd2

    /// @notice Construct the implementation for one Morpho Blue market.
    /// @param _morpho The Morpho Blue singleton contract.
    /// @param _arm The USDC ARM allowed to own and move this wrapper's position.
    /// @param _marketParams The complete Morpho market parameters; the loan token must be USDC for the USDC ARM.
    constructor(address _morpho, address _arm, MorphoMarketParams memory _marketParams) {
        if (_morpho == address(0)) revert InvalidMarket();
        if (_arm == address(0)) revert InvalidARM();
        if (_marketParams.loanToken == address(0) || _marketParams.irm == address(0)) revert InvalidMarket();

        morpho = IMorphoBlue(_morpho);
        arm = _arm;
        asset = _marketParams.loanToken;
        marketId = MorphoMarketId.wrap(keccak256(abi.encode(_marketParams)));
        _collateralToken = _marketParams.collateralToken;
        _oracle = _marketParams.oracle;
        _irm = _marketParams.irm;
        _lltv = _marketParams.lltv;

        MorphoMarketState memory state = morpho.market(marketId);
        if (state.lastUpdate == 0) revert InvalidMarket();

        _setOwner(address(0));
    }

    /// @notice Initialize a proxy's mutable reward configuration.
    /// @param _harvester The reward harvester.
    /// @param _merkleDistributor The distributor used for market incentive claims.
    function initialize(address _harvester, address _merkleDistributor) external initializer onlyOwner {
        _setHarvester(_harvester);
        _setMerkleDistributor(_merkleDistributor);
    }

    /// @notice Return the immutable configuration of this Morpho Blue market.
    function marketParams()
        external
        view
        returns (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv)
    {
        return (asset, _collateralToken, _oracle, _irm, _lltv);
    }

    function _marketParams() internal view returns (MorphoMarketParams memory) {
        return MorphoMarketParams({
            loanToken: asset, collateralToken: _collateralToken, oracle: _oracle, irm: _irm, lltv: _lltv
        });
    }

    /// @notice Supply an exact amount of loan assets to this wrapper's Morpho market.
    /// @dev Only the linked ARM may call this function and it must also be the receiver.
    ///      Morpho supply shares are owned by this wrapper rather than minted to the ARM.
    /// @param assets The amount of loan assets transferred from and supplied for the ARM.
    /// @param receiver The share owner for ERC-4626 compatibility; must be the linked ARM.
    /// @return shares The number of Morpho supply shares credited to this wrapper.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        if (msg.sender != arm || receiver != arm) revert OnlyARM();

        IERC20(asset).transferFrom(arm, address(this), assets);
        IERC20(asset).approve(address(morpho), assets);
        (, shares) = morpho.supply(_marketParams(), assets, 0, address(this), "");

        emit Deposit(arm, arm, assets, shares);
    }

    /// @notice Withdraw an exact amount of loan assets from Morpho to the linked ARM.
    /// @dev Only the linked ARM may call this function. Morpho rounds the required supply
    ///      shares up so the requested asset amount can be paid exactly.
    /// @param assets The exact amount of loan assets to withdraw.
    /// @param receiver The recipient of the loan assets; must be the linked ARM.
    /// @param owner The position owner for ERC-4626 compatibility; must be the linked ARM.
    /// @return shares The number of this wrapper's Morpho supply shares burned.
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        if (msg.sender != arm || receiver != arm || owner != arm) revert OnlyARM();

        (, shares) = morpho.withdraw(_marketParams(), assets, 0, address(this), arm);
        emit Withdraw(arm, arm, arm, assets, shares);
    }

    /// @notice Redeem an exact number of Morpho supply shares and send the assets to the linked ARM.
    /// @dev Only the linked ARM may call this function. Using shares permits a complete position
    ///      exit without leaving dust caused by asset-to-share rounding.
    /// @param shares The exact number of this wrapper's Morpho supply shares to burn.
    /// @param receiver The recipient of the loan assets; must be the linked ARM.
    /// @param owner The position owner for ERC-4626 compatibility; must be the linked ARM.
    /// @return assets The amount of loan assets withdrawn from Morpho.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        if (msg.sender != arm || receiver != arm || owner != arm) revert OnlyARM();

        (assets,) = morpho.withdraw(_marketParams(), 0, shares, address(this), arm);
        emit Withdraw(arm, arm, arm, assets, shares);
    }

    /// @notice Return the Morpho supply shares represented by this wrapper for an owner.
    /// @dev The linked ARM is the only recognized owner because Morpho records the actual
    ///      position against this wrapper. All other addresses have a zero balance.
    /// @param owner The account whose wrapper balance is requested.
    /// @return shares The wrapper's Morpho supply shares when `owner` is the ARM, otherwise zero.
    function balanceOf(address owner) public view returns (uint256 shares) {
        if (owner != arm) return 0;
        return morpho.position(marketId, address(this)).supplyShares;
    }

    /// @notice Convert loan assets to Morpho supply shares using projected current market state.
    /// @dev Includes interest and protocol-fee dilution accrued since Morpho's last state update,
    ///      and rounds down consistently with Morpho's asset-to-supply-share conversion.
    /// @param assets The amount of loan assets to convert.
    /// @return shares The corresponding number of Morpho supply shares, rounded down.
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        MorphoMarketState memory state = _expectedMarketState();
        return assets.mulDiv(
            uint256(state.totalSupplyShares) + VIRTUAL_SHARES,
            uint256(state.totalSupplyAssets) + VIRTUAL_ASSETS,
            Math.Rounding.Floor
        );
    }

    /// @notice Convert Morpho supply shares to loan assets using projected current market state.
    /// @dev Includes interest and protocol-fee dilution accrued since Morpho's last state update
    ///      and rounds down, matching the value realizable by redeeming the supplied shares.
    /// @param shares The number of Morpho supply shares to convert.
    /// @return assets The corresponding amount of loan assets, rounded down.
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        MorphoMarketState memory state = _expectedMarketState();
        return shares.mulDiv(
            uint256(state.totalSupplyAssets) + VIRTUAL_ASSETS,
            uint256(state.totalSupplyShares) + VIRTUAL_SHARES,
            Math.Rounding.Floor
        );
    }

    /// @notice Preview the loan assets received by redeeming Morpho supply shares.
    /// @param shares The number of Morpho supply shares that would be redeemed.
    /// @return assets The projected loan assets received, rounded down.
    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        return convertToAssets(shares);
    }

    /// @notice Return the maximum currently liquid amount withdrawable for an owner.
    /// @dev The result is limited by both the wrapper's position value and unborrowed liquidity
    ///      in this Morpho market. Returns zero for owners other than the linked ARM.
    /// @param owner The position owner; only the linked ARM can have a nonzero result.
    /// @return assets The maximum loan assets currently withdrawable.
    function maxWithdraw(address owner) external view returns (uint256 assets) {
        if (owner != arm) return 0;

        MorphoMarketState memory state = _expectedMarketState();
        uint256 positionAssets = _toAssetsDown(balanceOf(owner), state);
        uint256 marketLiquidity = uint256(state.totalSupplyAssets) - uint256(state.totalBorrowAssets);
        return Math.min(positionAssets, marketLiquidity);
    }

    /// @notice Return the maximum Morpho supply shares currently redeemable for an owner.
    /// @dev Converts the market's unborrowed liquidity into shares, rounds down, and caps the
    ///      result at this wrapper's balance. Returns zero for owners other than the linked ARM.
    /// @param owner The position owner; only the linked ARM can have a nonzero result.
    /// @return shares The maximum Morpho supply shares currently redeemable.
    function maxRedeem(address owner) external view returns (uint256 shares) {
        if (owner != arm) return 0;

        MorphoMarketState memory state = _expectedMarketState();
        uint256 positionShares = balanceOf(owner);
        uint256 marketLiquidity = uint256(state.totalSupplyAssets) - uint256(state.totalBorrowAssets);
        uint256 liquidShares = _toSharesDown(marketLiquidity, state);
        return Math.min(positionShares, liquidShares);
    }

    /// @notice Materialize pending Morpho interest without moving the ARM position.
    /// @dev Permissionless because Morpho interest accrual only updates market accounting.
    function accrueInterest() external {
        morpho.accrueInterest(_marketParams());
    }

    /// @notice Claim Merkle-distributed incentives allocated to this wrapper.
    /// @dev Permissionless submission is safe because the distributor always credits this wrapper.
    /// @param token The incentive token to claim.
    /// @param amount The cumulative claim amount committed by the distributor.
    /// @param proof The Merkle proof authorizing the wrapper's cumulative claim.
    function merkleClaim(address token, uint256 amount, bytes32[] calldata proof) external {
        address[] memory users = new address[](1);
        users[0] = address(this);
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = proof;
        merkleDistributor.claim(users, tokens, amounts, proofs);
    }

    /// @notice Collect claimed incentive tokens from this wrapper.
    /// @dev Only the configured harvester may call this function.
    ///      Loan-asset rewards are returned to the ARM so they increase ARM assets. Other reward
    ///      tokens are sent to the harvester for processing.
    /// @param tokens The incentive tokens to collect.
    /// @return amounts The amount of each corresponding token transferred.
    function collectRewards(address[] calldata tokens) external returns (uint256[] memory amounts) {
        if (msg.sender != harvester) revert OnlyHarvester();
        amounts = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            IERC20 token = IERC20(tokens[i]);
            amounts[i] = token.balanceOf(address(this));
            if (amounts[i] != 0) token.transfer(tokens[i] == asset ? arm : harvester, amounts[i]);
        }
        emit CollectedRewards(tokens, amounts);
    }

    /// @notice Set the account authorized to collect MORPHO incentives.
    /// @dev Callable only by the proxy owner. The zero address is rejected.
    /// @param _harvester The new reward harvester.
    function setHarvester(address _harvester) external onlyOwner {
        _setHarvester(_harvester);
    }

    /// @notice Set the distributor used to claim market incentives.
    /// @dev Callable only by the proxy owner. The zero address is rejected.
    /// @param _merkleDistributor The new Merkle distributor.
    function setMerkleDistributor(address _merkleDistributor) external onlyOwner {
        _setMerkleDistributor(_merkleDistributor);
    }

    /// @notice Recover ERC-20 tokens held directly by the wrapper.
    /// @dev Callable only by the proxy owner. The recipient must be the owner or harvester.
    ///      Passing zero for `amount` transfers the wrapper's complete token balance.
    /// @param token The ERC-20 token to transfer.
    /// @param to The owner or harvester receiving the tokens.
    /// @param amount The amount to transfer, or zero to transfer the complete balance.
    function transferTokens(address token, address to, uint256 amount) external onlyOwner {
        if (to != msg.sender && to != harvester) revert InvalidRecipient();
        amount = amount == 0 ? IERC20(token).balanceOf(address(this)) : amount;
        IERC20(token).transfer(to, amount);
    }

    function _setHarvester(address _harvester) internal {
        if (_harvester == address(0)) revert InvalidHarvester();
        harvester = _harvester;
        emit HarvesterUpdated(_harvester);
    }

    function _setMerkleDistributor(address _merkleDistributor) internal {
        if (_merkleDistributor == address(0)) revert InvalidMerkleDistributor();
        merkleDistributor = IDistributor(_merkleDistributor);
        emit MerkleDistributorUpdated(_merkleDistributor);
    }

    function _expectedMarketState() internal view returns (MorphoMarketState memory state) {
        state = morpho.market(marketId);
        uint256 elapsed = block.timestamp - uint256(state.lastUpdate);
        if (elapsed == 0 || state.totalBorrowAssets == 0) return state;

        MorphoMarketParams memory params = _marketParams();
        uint256 borrowRate = IMorphoIrm(_irm).borrowRateView(params, state);
        uint256 compoundedRate = _wTaylorCompounded(borrowRate, elapsed);
        uint256 interest = uint256(state.totalBorrowAssets).mulDiv(compoundedRate, WAD);

        state.totalBorrowAssets = uint128(uint256(state.totalBorrowAssets) + interest);
        state.totalSupplyAssets = uint128(uint256(state.totalSupplyAssets) + interest);

        if (state.fee != 0) {
            uint256 feeAssets = interest.mulDiv(uint256(state.fee), WAD);
            uint256 feeShares = feeAssets.mulDiv(
                uint256(state.totalSupplyShares) + VIRTUAL_SHARES,
                uint256(state.totalSupplyAssets) - feeAssets + VIRTUAL_ASSETS
            );
            state.totalSupplyShares = uint128(uint256(state.totalSupplyShares) + feeShares);
        }
    }

    function _toAssetsDown(uint256 shares, MorphoMarketState memory state) internal pure returns (uint256) {
        return shares.mulDiv(
            uint256(state.totalSupplyAssets) + VIRTUAL_ASSETS, uint256(state.totalSupplyShares) + VIRTUAL_SHARES
        );
    }

    function _toSharesDown(uint256 assets, MorphoMarketState memory state) internal pure returns (uint256) {
        return assets.mulDiv(
            uint256(state.totalSupplyShares) + VIRTUAL_SHARES, uint256(state.totalSupplyAssets) + VIRTUAL_ASSETS
        );
    }

    /// @dev Third-order Taylor approximation used by Morpho Blue for continuously compounded interest.
    function _wTaylorCompounded(uint256 ratePerSecond, uint256 elapsed) internal pure returns (uint256) {
        uint256 firstTerm = ratePerSecond * elapsed;
        uint256 secondTerm = firstTerm.mulDiv(firstTerm, 2 * WAD);
        uint256 thirdTerm = secondTerm.mulDiv(firstTerm, 3 * WAD);
        return firstTerm + secondTerm + thirdTerm;
    }
}
