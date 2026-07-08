// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {IWETH} from "contracts/Interfaces.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {StETHAssetAdapter} from "contracts/adapters/StETHAssetAdapter.sol";
import {WstETHAssetAdapter} from "contracts/adapters/WstETHAssetAdapter.sol";
import {EtherFiAssetAdapter} from "contracts/adapters/EtherFiAssetAdapter.sol";
import {WeETHAssetAdapter} from "contracts/adapters/WeETHAssetAdapter.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

/// @title Deploy the ETH-focused MultiAssetARM
/// @notice Deploys a single MultiAssetARM with WETH as the liquidity asset and four Lido/EtherFi base
///         assets: stETH, wstETH, eETH and weETH. Each base asset is wired to its redemption adapter
///         (Lido or EtherFi withdrawal queue). Ownership of the ARM, its CapManager and every adapter
///         proxy is handed to the mainnet 2/8 multisig (`MULTISIG_2_OF_8`); the operational role
///         ("strategist") is the Talos KMS relayer (`ARM_TALOS_RELAYER`).
/// @dev Mirrors the proven 011_DeployEtherFiARMScript structure, generalised to the unified
///      MultiAssetARM and the two extra Lido assets. No lending market is wired up here (idle WETH
///      stays in the ARM until a market is added in a follow-up script).
contract $036_DeployMultiAssetARMScript is AbstractDeployScript("036_DeployMultiAssetARMScript") {
    /// @dev Initial price band shared by every base asset, scaled to 1e36. The operator (Talos) tunes
    ///      these per asset via setPrices() after deployment.
    /// 0.99996e36 = base asset valued at 0.99996 WETH in totalAssets()
    uint256 internal constant CROSS_PRICE = 0.99996e36;
    /// 0.9997e36 = ARM pays 0.9997 WETH per base asset bought from traders (must stay below cross)
    uint256 internal constant BUY_PRICE = 0.9997e36;
    /// 1e36 = ARM charges 1 WETH per base asset sold to traders (must stay at/above cross)
    uint256 internal constant SELL_PRICE = 1e36;

    function _execute() internal override {
        // 1. Deploy the ARM proxy.
        Proxy armProxy = new Proxy();
        _recordDeployment("ETH_ARM", address(armProxy));

        // 2. Deploy the CapManager (proxy + implementation), owned by the 2/8 multisig and operated by Talos.
        Proxy capManProxy = new Proxy();
        _recordDeployment("ETH_ARM_CAP_MAN", address(capManProxy));

        CapManager capManagerImpl = new CapManager(address(armProxy));
        _recordDeployment("ETH_ARM_CAP_IMPL", address(capManagerImpl));

        // Initialize the CapManager with the 2/8 multisig as operator; keep the deployer as owner for now.
        bytes memory capManData = abi.encodeWithSignature("initialize(address)", Mainnet.MULTISIG_2_OF_8);
        capManProxy.initialize(address(capManagerImpl), deployer, capManData);
        CapManager capManager = CapManager(address(capManProxy));

        // 3. Set the initial total-assets cap and per-LP caps. Tuned later by the CapManager operator.
        capManager.setTotalAssetsCap(250 ether);
        capManager.setAccountCapEnabled(true);
        address[] memory lpAccounts = new address[](1);
        lpAccounts[0] = Mainnet.TREASURY_LP;
        capManager.setLiquidityProviderCaps(lpAccounts, 250 ether);

        // 4. Hand the CapManager to the 2/8 multisig.
        capManProxy.setOwner(Mainnet.MULTISIG_2_OF_8);

        // 5. Deploy the MultiAssetARM implementation (WETH liquidity asset).
        MultiAssetARM armImpl = new MultiAssetARM({
            _liquidityAsset: Mainnet.WETH, _claimDelay: 10 minutes, _minSharesToRedeem: 1e7, _allocateThreshold: 1 ether
        });
        _recordDeployment("ETH_ARM_IMPL", address(armImpl));

        // 6. Give the deployer the MIN_LIQUIDITY (1e12 WETH) that initialize() pulls to seed dead shares.
        IWETH(Mainnet.WETH).deposit{value: 1e12}();
        IWETH(Mainnet.WETH).approve(address(armProxy), 1e12);

        // 7. Initialize the ARM proxy: deployer stays owner during setup, Talos is the operator.
        bytes memory armData = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address,address)",
            "ETH ARM", // name
            "ARM-ETH", // symbol
            Mainnet.ARM_TALOS_RELAYER, // operator
            2000, // 20% performance fee
            Mainnet.BUYBACK_OPERATOR, // fee collector
            address(capManager)
        );
        armProxy.initialize(address(armImpl), deployer, armData);
        MultiAssetARM arm = MultiAssetARM(payable(address(armProxy)));

        // 8. Deploy the stETH adapter (pegged 1:1) and register stETH.
        {
            StETHAssetAdapter adapterImpl =
                new StETHAssetAdapter(address(armProxy), Mainnet.WETH, Mainnet.STETH, Mainnet.LIDO_WITHDRAWAL);
            _recordDeployment("ETH_ARM_STETH_ADAPTER_IMPL", address(adapterImpl));
            Proxy adapterProxy = new Proxy();
            adapterProxy.initialize(
                address(adapterImpl), Mainnet.MULTISIG_2_OF_8, abi.encodeWithSignature("initialize()")
            );
            _recordDeployment("ETH_ARM_STETH_ADAPTER", address(adapterProxy));
            arm.addBaseAsset(
                Mainnet.STETH,
                address(adapterProxy),
                BUY_PRICE,
                SELL_PRICE,
                type(uint128).max,
                type(uint128).max,
                CROSS_PRICE,
                true
            );
        }

        // 9. Deploy the wstETH adapter (non-pegged wrapper) and register wstETH.
        {
            WstETHAssetAdapter adapterImpl = new WstETHAssetAdapter(
                address(armProxy), Mainnet.WETH, Mainnet.STETH, Mainnet.WSTETH, Mainnet.LIDO_WITHDRAWAL
            );
            _recordDeployment("ETH_ARM_WSTETH_ADAPTER_IMPL", address(adapterImpl));
            Proxy adapterProxy = new Proxy();
            adapterProxy.initialize(
                address(adapterImpl), Mainnet.MULTISIG_2_OF_8, abi.encodeWithSignature("initialize()")
            );
            _recordDeployment("ETH_ARM_WSTETH_ADAPTER", address(adapterProxy));
            arm.addBaseAsset(
                Mainnet.WSTETH,
                address(adapterProxy),
                BUY_PRICE,
                SELL_PRICE,
                type(uint128).max,
                type(uint128).max,
                CROSS_PRICE,
                false
            );
        }

        // 10. Deploy the eETH adapter (pegged 1:1) and register eETH.
        {
            EtherFiAssetAdapter adapterImpl = new EtherFiAssetAdapter(
                address(armProxy),
                Mainnet.EETH,
                Mainnet.WETH,
                Mainnet.ETHERFI_WITHDRAWAL,
                Mainnet.ETHERFI_WITHDRAWAL_NFT
            );
            _recordDeployment("ETH_ARM_EETH_ADAPTER_IMPL", address(adapterImpl));
            Proxy adapterProxy = new Proxy();
            adapterProxy.initialize(
                address(adapterImpl), Mainnet.MULTISIG_2_OF_8, abi.encodeWithSignature("initialize()")
            );
            _recordDeployment("ETH_ARM_EETH_ADAPTER", address(adapterProxy));
            arm.addBaseAsset(
                Mainnet.EETH,
                address(adapterProxy),
                BUY_PRICE,
                SELL_PRICE,
                type(uint128).max,
                type(uint128).max,
                CROSS_PRICE,
                true
            );
        }

        // 11. Deploy the weETH adapter (non-pegged wrapper) and register weETH.
        {
            WeETHAssetAdapter adapterImpl = new WeETHAssetAdapter(
                address(armProxy),
                Mainnet.WEETH,
                Mainnet.EETH,
                Mainnet.WETH,
                Mainnet.ETHERFI_WITHDRAWAL,
                Mainnet.ETHERFI_WITHDRAWAL_NFT
            );
            _recordDeployment("ETH_ARM_WEETH_ADAPTER_IMPL", address(adapterImpl));
            Proxy adapterProxy = new Proxy();
            adapterProxy.initialize(
                address(adapterImpl), Mainnet.MULTISIG_2_OF_8, abi.encodeWithSignature("initialize()")
            );
            _recordDeployment("ETH_ARM_WEETH_ADAPTER", address(adapterProxy));
            arm.addBaseAsset(
                Mainnet.WEETH,
                address(adapterProxy),
                BUY_PRICE,
                SELL_PRICE,
                type(uint128).max,
                type(uint128).max,
                CROSS_PRICE,
                false
            );
        }

        // 12. Hand ownership of the ARM to the 2/8 multisig.
        armProxy.setOwner(Mainnet.MULTISIG_2_OF_8);
    }
}
