// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {MorphoBlueMarket, MorphoMarketId, MorphoMarketParams} from "contracts/markets/MorphoBlueMarket.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

/// @title Deploy direct Morpho Blue markets for the USDC ARM
/// @notice Deploys four immutable MorphoBlueMarket implementations and their proxies for OETH/USDC,
///         WBTC/USDC, and two cbBTC/USDC markets. The proxies are registered as supported USDC ARM
///         markets but no market is activated automatically.
/// @dev The two cbBTC markets use the same collateral, loan token, IRM, and LLTV but distinct
///      oracle addresses. Expected market IDs are asserted before deployment.
contract $043_DeployUSDCMorphoBlueMarketsScript is AbstractDeployScript("043_DeployUSDCMorphoBlueMarketsScript") {
    address internal constant OWNER = Mainnet.MULTISIG_5_OF_8;
    address internal constant HARVESTER = Mainnet.BUYBACK_OPERATOR;

    address internal constant ADAPTIVE_CURVE_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint256 internal constant LLTV_86_PERCENT = 0.86e18;

    bytes32 internal constant OETH_USDC_ID = 0xb8fef900b383db2dbbf4458c7f46acf5b140f26d603a6d1829963f241b82510e;
    bytes32 internal constant WBTC_USDC_ID = 0x3a85e619751152991742810df6ec69ce473daef99e28a64ab2340d7b7ccfee49;
    bytes32 internal constant CBBTC_USDC_C7BE_ID = 0xba3ba077d9c838696b76e29a394ae9f0d1517a372e30fd9a0fc19c516fb4c5a7;
    bytes32 internal constant CBBTC_USDC_A6D6_ID = 0x64d65c9a2d91c36d56fbc42d69e979335320169b3df63bf92789e2c8883fcc64;

    address internal constant OETH_USDC_ORACLE = 0xE8aDfF9117151fb5ad7313873780b87cC56EEDB0;
    address internal constant WBTC_USDC_ORACLE = 0xDddd770BADd886dF3864029e4B377B5F6a2B6b83;
    address internal constant CBBTC_USDC_C7BE_ORACLE = 0xc7BE7593FD5453Db5AdcC1d7103f2211d4F2e40D;
    address internal constant CBBTC_USDC_A6D6_ORACLE = 0xA6D6950c9F177F1De7f7757FB33539e3Ec60182a;

    function _execute() internal override {
        address usdcARM = resolver.resolve("USDC_ARM");

        _deployMarket("USDC_ARM_MORPHO_BLUE_OETH", usdcARM, _params(Mainnet.OETH, OETH_USDC_ORACLE), OETH_USDC_ID);
        _deployMarket("USDC_ARM_MORPHO_BLUE_WBTC", usdcARM, _params(Mainnet.WBTC, WBTC_USDC_ORACLE), WBTC_USDC_ID);
        _deployMarket(
            "USDC_ARM_MORPHO_BLUE_CBBTC_BA3BA077",
            usdcARM,
            _params(Mainnet.CBBTC, CBBTC_USDC_C7BE_ORACLE),
            CBBTC_USDC_C7BE_ID
        );
        _deployMarket(
            "USDC_ARM_MORPHO_BLUE_CBBTC_64D65C9A",
            usdcARM,
            _params(Mainnet.CBBTC, CBBTC_USDC_A6D6_ORACLE),
            CBBTC_USDC_A6D6_ID
        );
    }

    function _fork() internal override {
        MultiAssetARM usdcARM = MultiAssetARM(payable(resolver.resolve("USDC_ARM")));
        address[] memory markets = _deployedMarkets();

        uint256 unsupportedCount;
        for (uint256 i; i < markets.length; ++i) {
            if (!usdcARM.supportedMarkets(markets[i])) ++unsupportedCount;
        }
        if (unsupportedCount == 0) return;

        address[] memory unsupportedMarkets = new address[](unsupportedCount);
        uint256 next;
        for (uint256 i; i < markets.length; ++i) {
            if (!usdcARM.supportedMarkets(markets[i])) unsupportedMarkets[next++] = markets[i];
        }

        // Registration is an owner action. The operator can subsequently choose among these
        // wrappers with setActiveMarket without granting it authority to add arbitrary markets.
        vm.prank(usdcARM.owner());
        usdcARM.addMarkets(unsupportedMarkets);
    }

    function _deployMarket(
        string memory deploymentName,
        address usdcARM,
        MorphoMarketParams memory params,
        bytes32 expectedId
    ) internal {
        require(keccak256(abi.encode(params)) == expectedId, "Unexpected Morpho market ID");

        MorphoBlueMarket implementation = new MorphoBlueMarket(Mainnet.MORPHO_BLUE, usdcARM, params);
        _recordDeployment(string.concat(deploymentName, "_IMPL"), address(implementation));

        Proxy marketProxy = new Proxy();
        _recordDeployment(deploymentName, address(marketProxy));
        marketProxy.initialize(
            address(implementation),
            OWNER,
            abi.encodeCall(MorphoBlueMarket.initialize, (HARVESTER, Mainnet.MERKLE_DISTRIBUTOR))
        );

        require(
            MorphoMarketId.unwrap(MorphoBlueMarket(address(marketProxy)).marketId()) == expectedId,
            "Initialized wrong Morpho market"
        );
    }

    function _params(address collateralToken, address oracle) internal pure returns (MorphoMarketParams memory) {
        return MorphoMarketParams({
            loanToken: Mainnet.USDC,
            collateralToken: collateralToken,
            oracle: oracle,
            irm: ADAPTIVE_CURVE_IRM,
            lltv: LLTV_86_PERCENT
        });
    }

    function _deployedMarkets() internal view returns (address[] memory markets) {
        markets = new address[](4);
        markets[0] = resolver.resolve("USDC_ARM_MORPHO_BLUE_OETH");
        markets[1] = resolver.resolve("USDC_ARM_MORPHO_BLUE_WBTC");
        markets[2] = resolver.resolve("USDC_ARM_MORPHO_BLUE_CBBTC_BA3BA077");
        markets[3] = resolver.resolve("USDC_ARM_MORPHO_BLUE_CBBTC_64D65C9A");
    }
}
