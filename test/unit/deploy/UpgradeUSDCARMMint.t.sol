// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {Resolver} from "script/deploy/helpers/Resolver.sol";
import {State} from "script/deploy/helpers/DeploymentTypes.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";

contract Unit_UpgradeUSDCARMMintDeployment_Test is Test {
    function test_DeploymentArtifactHasNoUnlinkedLibraries() external {
        string memory artifact = string.concat(
            vm.projectRoot(), "/out/043_UpgradeUSDCARMMintScript.s.sol/$043_UpgradeUSDCARMMintScript.json"
        );
        address deployment = vm.deployCode(artifact);

        assertEq(AbstractDeployScript(deployment).name(), "043_UpgradeUSDCARMMintScript");
    }

    function test_ExecuteDeploysLinkedImplementation() external {
        MockERC20 token = new MockERC20("USD", "USD", 6);
        vm.etch(Mainnet.USDC, address(token).code);
        vm.etch(Mainnet.PYUSD, address(token).code);
        vm.etch(Mainnet.USDG, address(token).code);

        address resolverAddress = address(uint160(uint256(keccak256("Resolver"))));
        Resolver resolverImplementation = new Resolver();
        vm.etch(resolverAddress, address(resolverImplementation).code);
        Resolver resolver = Resolver(resolverAddress);
        resolver.setState(State.REAL_DEPLOYING);
        resolver.addContract("USDC_ARM", makeAddr("usdcARM"));

        vm.setEnv("DEPLOYER_ADDRESS", vm.toString(address(this)));
        address deployment = vm.deployCode(
            string.concat(
                vm.projectRoot(), "/out/043_UpgradeUSDCARMMintScript.s.sol/$043_UpgradeUSDCARMMintScript.json"
            )
        );
        AbstractDeployScript(deployment).run();

        MultiAssetARM implementation = MultiAssetARM(payable(resolver.resolve("USDC_ARM_IMPL")));
        assertEq(implementation.liquidityAsset(), Mainnet.USDC);
        assertGt(resolver.resolve("ARM_ADAPTER_LIB").code.length, 0);
    }
}
