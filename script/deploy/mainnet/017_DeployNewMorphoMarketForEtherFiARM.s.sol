// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contract imports
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $017_DeployNewMorphoMarketForEtherFiARM is AbstractDeployScript("017_DeployNewMorphoMarketForEtherFiARM") {
    Proxy morphoMarketProxy;
    MorphoMarket morphoMarket;

    function _execute() internal override {
        // 1. Deploy MorphoMarket proxy
        morphoMarketProxy = new Proxy();
        _recordDeployment("MORPHO_MARKET_ETHERFI", address(morphoMarketProxy));

        // 2. Deploy MorphoMarket
        morphoMarket = new MorphoMarket(Mainnet.ETHERFI_ARM, Mainnet.MORPHO_MARKET_OETH_VAULT);
        _recordDeployment("MORPHO_MARKET_ETHERFI_IMPL", address(morphoMarket));

        // 3. Initialize MorphoMarket proxy with the implementation, Timelock as owner
        bytes memory data = abi.encodeWithSelector(
            Abstract4626MarketWrapper.initialize.selector, Mainnet.STRATEGIST, Mainnet.MERKLE_DISTRIBUTOR
        );
        morphoMarketProxy.initialize(address(morphoMarket), Mainnet.TIMELOCK, data);
    }
}
