// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Proxy} from "contracts/Proxy.sol";
import {CapManager} from "contracts/CapManager.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {StablesARM} from "contracts/StablesARM.sol";
import {PaxosAssetAdapter} from "contracts/adapters/PaxosAssetAdapter.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

contract $034_DeployStablesARMScript is AbstractDeployScript("034_DeployStablesARMScript") {
    uint256 internal constant TOTAL_ASSETS_CAP = 100_000e6;
    uint256 internal constant LP_ACCOUNT_CAP = 20_000e6;
    uint256 internal constant BUY_PRICE = 0.998e36;
    uint256 internal constant SELL_PRICE = 1e36;
    uint256 internal constant CROSS_PRICE = 0.999e36;

    function _execute() internal override {
        Proxy armProxy = new Proxy();
        _recordDeployment("STABLES_ARM", address(armProxy));

        Proxy capManProxy = new Proxy();
        _recordDeployment("STABLES_ARM_CAP_MAN", address(capManProxy));

        CapManager capManagerImpl = new CapManager(address(armProxy));
        _recordDeployment("STABLES_ARM_CAP_IMPL", address(capManagerImpl));

        capManProxy.initialize(
            address(capManagerImpl),
            deployer,
            abi.encodeWithSelector(CapManager.initialize.selector, Mainnet.ARM_TALOS_RELAYER)
        );
        CapManager capManager = CapManager(address(capManProxy));

        capManager.setTotalAssetsCap(uint248(TOTAL_ASSETS_CAP));
        capManager.setAccountCapEnabled(true);
        address[] memory lpAccounts = new address[](7);
        lpAccounts[0] = Mainnet.TREASURY_LP;
        lpAccounts[1] = 0x8ac3b96d118288427055ae7f62e407fC7c482F57;
        lpAccounts[2] = 0x49aFBb19ebAd01274707A7226A34D5297B6dAf75;
        lpAccounts[3] = 0xF2B8C142Edcf2f3Cc22665cCE863a7C9A3E9F156;
        lpAccounts[4] = 0x8fAEE3092ef992FC3BD5BdAF496C30a3Ae1066c6;
        lpAccounts[5] = 0xE6030d4E773888e1DfE4CC31DA6e05bfe53091ac;
        lpAccounts[6] = 0x86D888C3fA8A7F67452eF2Eccc1C5EE9751Ec8d6;
        capManager.setLiquidityProviderCaps(lpAccounts, LP_ACCOUNT_CAP);

        capManProxy.setOwner(Mainnet.GOV_MULTISIG);

        StablesARM armImpl = new StablesARM(Mainnet.USDC, 10 minutes, 1e6, 100e6);
        _recordDeployment("STABLES_ARM_IMPL", address(armImpl));

        IERC20(Mainnet.USDC).approve(address(armProxy), 1000);
        armProxy.initialize(
            address(armImpl),
            deployer,
            abi.encodeWithSelector(
                StablesARM.initialize.selector,
                "StablesARM",
                "ARM-USDC-Stables",
                Mainnet.ARM_TALOS_RELAYER,
                2000,
                Mainnet.BUYBACK_OPERATOR,
                address(capManager)
            )
        );

        PaxosAssetAdapter usdgAdapterImpl = new PaxosAssetAdapter(address(armProxy), Mainnet.USDG, Mainnet.USDC);
        _recordDeployment("STABLES_ARM_USDG_ADAPTER_IMPL", address(usdgAdapterImpl));
        Proxy usdgAdapterProxy = new Proxy();
        usdgAdapterProxy.initialize(
            address(usdgAdapterImpl),
            Mainnet.TIMELOCK,
            abi.encodeWithSelector(PaxosAssetAdapter.initialize.selector, Mainnet.ARM_TALOS_RELAYER, address(0))
        );
        _recordDeployment("STABLES_ARM_USDG_ADAPTER", address(usdgAdapterProxy));

        PaxosAssetAdapter pyusdAdapterImpl = new PaxosAssetAdapter(address(armProxy), Mainnet.PYUSD, Mainnet.USDC);
        _recordDeployment("STABLES_ARM_PYUSD_ADAPTER_IMPL", address(pyusdAdapterImpl));
        Proxy pyusdAdapterProxy = new Proxy();
        pyusdAdapterProxy.initialize(
            address(pyusdAdapterImpl),
            Mainnet.TIMELOCK,
            abi.encodeWithSelector(PaxosAssetAdapter.initialize.selector, Mainnet.ARM_TALOS_RELAYER, address(0))
        );
        _recordDeployment("STABLES_ARM_PYUSD_ADAPTER", address(pyusdAdapterProxy));

        StablesARM arm = StablesARM(payable(address(armProxy)));
        arm.addBaseAsset(
            Mainnet.USDG,
            address(usdgAdapterProxy),
            BUY_PRICE,
            SELL_PRICE,
            type(uint128).max,
            type(uint128).max,
            CROSS_PRICE,
            true
        );
        arm.addBaseAsset(
            Mainnet.PYUSD,
            address(pyusdAdapterProxy),
            BUY_PRICE,
            SELL_PRICE,
            type(uint128).max,
            type(uint128).max,
            CROSS_PRICE,
            true
        );

        armProxy.setOwner(Mainnet.GOV_MULTISIG);
    }
}
