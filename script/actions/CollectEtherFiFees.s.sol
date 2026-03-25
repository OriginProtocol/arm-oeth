// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";
import {AbstractARM} from "src/contracts/AbstractARM.sol";

contract CollectEtherFiFees is Script {
    function run() external {
        // Get the address of the EtherFiFeesCollector contract from the Resolver
        AbstractARM EtherFiARM = AbstractARM(0xfB0A3CF9B019BFd8827443d131b235B3E0FC58d2);

        // Call the collectFees function on the EtherFiFeesCollector contract
        vm.startBroadcast();
        EtherFiARM.collectFees();
        vm.stopBroadcast();
    }
}
