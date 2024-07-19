// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Test} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OEthARM} from "contracts/OethARM.sol";

// Utils
import {Mainnet} from "test/utils/Addresses.sol";

contract OETHARMScript is Script {
    // Fetch PK from env and derive the deployer address
    address public deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function run() public {
        // 🟡 All the next transactions will be sent by the deployer if `--broadcast`option is used on the command line 🟡
        vm.startBroadcast(deployer);

        // 1. Deploy proxy contracts
        Proxy proxy = new Proxy();

        // 2. Deploy implementation
        OEthARM oethARMImple = new OEthARM();

        // 3. Initialize proxy
        proxy.initialize(address(oethARMImple), Mainnet.TIMELOCK, "");

        // Stop broadcasting
        vm.stopBroadcast();
    }
}
