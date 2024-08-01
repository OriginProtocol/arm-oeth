// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OEthARM} from "contracts/OethARM.sol";

// Utils
import {AddressResolver} from "contracts/utils/Addresses.sol";

/// @notice Deploy the OEthARM contract using a proxy.
/// @dev 1. Deploy the proxy contract.
///      2. Deploy the OEthARM implementation contract.
///      3. Initialize the proxy contract with the OEthARM implementation contract.
contract _001_OETHARMScript is Script {
    AddressResolver public resolver = new AddressResolver();
    address public deployer;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual {
        if (vm.envExists("DEPLOYER_PRIVATE_KEY")) {
            console.log("Using real deployer address");
            // Fetch PK from env and derive the deployer address
            deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        } else {
            console.log("Using default deployer address");
            // If no PK is provided, use a default deployer address
            deployer = makeAddr("deployer");
        }
    }

    //////////////////////////////////////////////////////
    /// --- RUN
    //////////////////////////////////////////////////////
    function run() public {
        // 🟡 All the next transactions will be sent by the deployer if `--broadcast`option is used on the command line 🟡
        vm.startBroadcast(deployer);

        // 1. Deploy proxy contracts
        Proxy proxy = new Proxy();

        // 2. Deploy implementation
        OEthARM oethARMImpl =
            new OEthARM(resolver.resolve("OETH"), resolver.resolve("WETH"), resolver.resolve("OETH_VAULT"));

        // 3. Initialize proxy, set the owner and operator
        address governor = resolver.resolve("GOVERNOR");
        address operator = resolver.resolve("OPERATOR");
        bytes memory data = abi.encodeWithSignature("setOperator(address)", operator);
        proxy.initialize(address(oethARMImpl), governor, data);

        // Stop broadcasting
        vm.stopBroadcast();
    }
}
