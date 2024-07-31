// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

// Contracts
import {OEthARM} from "contracts/OethARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Utils
import {Mainnet} from "contracts/utils/Addresses.sol";

contract _999_TasksScript is Script {
    address public deployer;

    bytes32 emptyStringHash = keccak256(abi.encodePacked(""));
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////

    function setUp() public {
        if (vm.envExists("DEPLOYER_PRIVATE_KEY")) {
            console.log("Deployer private key found in env");
            // Fetch PK from env and derive the deployer address
            deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        } else {
            // If no PK is provided, use a default deployer address
            deployer = makeAddr("deployer");
        }
    }

    //////////////////////////////////////////////////////
    /// --- TASKS
    //////////////////////////////////////////////////////
    function swap(address from, address to, uint256 amount) public {
        vm.startBroadcast(deployer);

        if (from != address(0) && to != address(0)) {
            revert("Cannot specify both from and to asset. It has to be one or the other");
        }

        if (from != address(0)) {
            require(from == Mainnet.OETH || from == Mainnet.WETH, "Invalid from asset");

            to = from == Mainnet.OETH ? Mainnet.WETH : Mainnet.OETH;

            string memory message = string(
                abi.encodePacked(
                    "About to swap ",
                    vm.toString(amount),
                    " ",
                    vm.toString(from),
                    " to ",
                    vm.toString(to),
                    " for ",
                    vm.toString(deployer)
                )
            );

            console.log(message);

            // Execute the swap
            OEthARM(Mainnet.OETH_ARM).swapExactTokensForTokens(IERC20(from), IERC20(to), amount, 0, deployer);
        } else if (to != address(0)) {
            require(to == Mainnet.OETH || to == Mainnet.WETH, "Invalid to asset");

            from = to == Mainnet.OETH ? Mainnet.WETH : Mainnet.OETH;

            string memory message = string(
                abi.encodePacked(
                    "About to swap ",
                    vm.toString(from),
                    " to ",
                    vm.toString(amount),
                    " ",
                    vm.toString(to),
                    " for ",
                    vm.toString(deployer)
                )
            );

            console.log(message);

            // Execute the swap
            OEthARM(Mainnet.OETH_ARM).swapTokensForExactTokens(
                IERC20(from), IERC20(to), amount, type(uint256).max, deployer
            );
        } else {
            revert("Must specify either from or to asset");
        }

        vm.stopBroadcast();
    }
}
