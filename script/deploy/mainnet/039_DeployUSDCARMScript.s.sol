// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {PaxosAssetAdapter} from "contracts/adapters/PaxosAssetAdapter.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {State} from "script/deploy/helpers/DeploymentTypes.sol";

/// @title Redeploy the USDC ARM with Paxos base assets
/// @notice Deploys a single MultiAssetARM with USDC as the liquidity asset and two Paxos-issued
///         base assets: PYUSD and USDG. Each base asset is wired to its own PaxosAssetAdapter,
///         whose redemption queue is fully off-chain: the operator submits queued base assets to a
///         Paxos deposit address and Paxos Actions settle USDC 1:1 back to the adapter. Ownership
///         of the ARM, its CapManager and both adapter proxies is handed to the multi-chain 2/8
///         multisig (`MULTISIG_2_OF_8`); the operational role is the Talos KMS relayer
///         (`ARM_TALOS_RELAYER`).
/// @dev Recreates the complete stack originally deployed by `037_DeployUSDARMScript` under
///      USDC-specific ERC-20 metadata and resolver keys. The adapters' `paxosRecipient` is set to a
///      placeholder at deployment - the adapter owner replaces it with the real Paxos deposit
///      address via setPaxosRecipient() once Paxos provides it. No lending market is wired up here
///      (idle USDC stays in the ARM until a market is added in a follow-up script).
contract $039_DeployUSDCARMScript is AbstractDeployScript("039_DeployUSDCARMScript") {
    /// @dev Owner of the ARM, CapManager and both PaxosAssetAdapter proxies: the multi-chain 2/8 multisig.
    address internal constant OWNER_2_OF_8 = Mainnet.MULTISIG_2_OF_8;
    /// @dev Operational role (request/claim redemptions, submit Paxos redeems, set prices): the
    ///      Talos KMS relayer.
    address internal constant OPERATOR_TALOS = Mainnet.ARM_TALOS_RELAYER;

    /// @dev Initial price band shared by both Paxos base assets, scaled to 1e36. The operator
    ///      (Talos) tunes these per asset via setPrices() after deployment.
    /// 0.99997e36 = base asset valued at 0.99997 USDC in totalAssets() (0.3 bps discount, as the
    ///              Paxos assets trade at around 1 bps)
    uint256 internal constant CROSS_PRICE = 0.99997e36;
    /// 0.998e36 = ARM pays 0.998 USDC per base asset bought from traders (must stay below cross)
    uint256 internal constant BUY_PRICE = 0.998e36;
    /// 1e36 = ARM charges 1 USDC per base asset sold to traders (must stay at/above cross)
    uint256 internal constant SELL_PRICE = 1e36;

    /// @dev Sky/Maker LitePSM, the largest USDC holder (~4.25B USDC at the pinned fork block).
    ///      Used only in fork states to seed the pranked deployer with the MIN_LIQUIDITY dust that
    ///      initialize() pulls.
    address internal constant USDC_WHALE = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;
    /// @dev 1000 = 0.001 USDC. Comfortable margin over the 1 atomic unit
    ///      of USDC (0.000001 USDC) that initialize() pulls.
    uint256 internal constant USDC_SEED = 1000;

    function _execute() internal override {
        // 1. Deploy the ARM proxy.
        Proxy armProxy = new Proxy();
        _recordDeployment("USDC_ARM", address(armProxy));

        // 2. Deploy the CapManager (proxy + implementation), owned by the 2/8 multisig and
        //    operated by Talos.
        Proxy capManProxy = new Proxy();
        _recordDeployment("USDC_ARM_CAP_MAN", address(capManProxy));

        CapManager capManagerImpl = new CapManager(address(armProxy));
        _recordDeployment("USDC_ARM_CAP_IMPL", address(capManagerImpl));

        // Initialize the CapManager with Talos as operator; keep the deployer as owner for now.
        bytes memory capManData = abi.encodeWithSignature("initialize(address)", OPERATOR_TALOS);
        capManProxy.initialize(address(capManagerImpl), deployer, capManData);
        CapManager capManager = CapManager(address(capManProxy));

        // 3. Set the initial total-assets cap and per-LP caps. Tuned later by the CapManager operator.
        capManager.setTotalAssetsCap(uint248(100_000e6)); // 100,000 USDC
        capManager.setAccountCapEnabled(true);
        address[] memory lpAccounts = new address[](1);
        lpAccounts[0] = Mainnet.TREASURY_LP;
        capManager.setLiquidityProviderCaps(lpAccounts, 100_000e6); // 100,000 USDC

        // 4. Hand the CapManager to the 2/8 multisig.
        capManProxy.setOwner(OWNER_2_OF_8);

        // 5. Deploy the MultiAssetARM implementation (USDC liquidity asset). The parameters are the
        //    6-decimal analogues of 035's 18-decimal WETH values: 1e6 = 1 USDC minimum market
        //    shares to redeem (vs 1e7 wei WETH), 100e6 = 100 USDC allocate threshold (vs 1 WETH).
        MultiAssetARM armImpl = new MultiAssetARM({
            _liquidityAsset: Mainnet.USDC, _claimDelay: 10 minutes, _minSharesToRedeem: 1e6, _allocateThreshold: 100e6
        });
        _recordDeployment("USDC_ARM_IMPL", address(armImpl));

        // 6. Give the deployer the MIN_LIQUIDITY (1 atomic unit of USDC, i.e. 0.000001 USDC) that
        //    initialize() pulls to seed dead shares. 035 wraps ETH into WETH for this, but USDC
        //    cannot be wrapped from ETH and the pranked deployer holds no USDC on a fork, so in
        //    fork states a dust amount is borrowed from the Sky/Maker LitePSM whale.
        //    In REAL_DEPLOYING the deployer wallet must already hold at least 1 atomic unit of USDC.
        if (state != State.REAL_DEPLOYING) {
            vm.stopPrank();
            vm.prank(USDC_WHALE);
            IERC20(Mainnet.USDC).transfer(deployer, USDC_SEED);
            vm.startPrank(deployer);
        }
        IERC20(Mainnet.USDC).approve(address(armProxy), USDC_SEED);

        // 7. Initialize the ARM proxy: deployer stays owner during setup, Talos is the operator.
        bytes memory armData = abi.encodeWithSignature(
            "initialize(string,string,address,uint256,address,address)",
            "USDC ARM", // name
            "ARM-USDC", // symbol
            OPERATOR_TALOS, // operator
            2000, // 20% performance fee
            Mainnet.BUYBACK_OPERATOR, // fee collector
            address(capManager)
        );
        armProxy.initialize(address(armImpl), deployer, armData);
        MultiAssetARM arm = MultiAssetARM(payable(address(armProxy)));

        // 8. Deploy the PYUSD Paxos adapter (pegged 1:1) and register PYUSD.
        {
            PaxosAssetAdapter adapterImpl = new PaxosAssetAdapter(address(armProxy), Mainnet.PYUSD, Mainnet.USDC);
            _recordDeployment("USDC_ARM_PYUSD_ADAPTER_IMPL", address(adapterImpl));
            Proxy adapterProxy = new Proxy();
            // paxosRecipient is a placeholder - the 2/8 multisig owner replaces it via setPaxosRecipient().
            adapterProxy.initialize(
                address(adapterImpl),
                OWNER_2_OF_8,
                abi.encodeWithSelector(PaxosAssetAdapter.initialize.selector, OPERATOR_TALOS, Mainnet.PAXOS_RECIPIENT)
            );
            _recordDeployment("USDC_ARM_PYUSD_ADAPTER", address(adapterProxy));
            arm.addBaseAsset(
                Mainnet.PYUSD,
                address(adapterProxy),
                BUY_PRICE,
                SELL_PRICE,
                0, // buyAmount: no swaps until the Operator sets the swap limits via setPrices()
                0, // sellAmount
                CROSS_PRICE,
                true
            );
        }

        // 9. Deploy the USDG Paxos adapter (pegged 1:1) and register USDG.
        {
            PaxosAssetAdapter adapterImpl = new PaxosAssetAdapter(address(armProxy), Mainnet.USDG, Mainnet.USDC);
            _recordDeployment("USDC_ARM_USDG_ADAPTER_IMPL", address(adapterImpl));
            Proxy adapterProxy = new Proxy();
            // paxosRecipient is a placeholder - the 2/8 multisig owner replaces it via setPaxosRecipient().
            adapterProxy.initialize(
                address(adapterImpl),
                OWNER_2_OF_8,
                abi.encodeWithSelector(PaxosAssetAdapter.initialize.selector, OPERATOR_TALOS, Mainnet.PAXOS_RECIPIENT)
            );
            _recordDeployment("USDC_ARM_USDG_ADAPTER", address(adapterProxy));
            arm.addBaseAsset(
                Mainnet.USDG,
                address(adapterProxy),
                BUY_PRICE,
                SELL_PRICE,
                0, // buyAmount: no swaps until the Operator sets the swap limits via setPrices()
                0, // sellAmount
                CROSS_PRICE,
                true
            );
        }

        // 10. Hand ownership of the ARM to the 2/8 multisig. The owner will later be moved to the
        //     Timelock (governance) before the CapManager is removed.
        armProxy.setOwner(OWNER_2_OF_8);
    }
}
