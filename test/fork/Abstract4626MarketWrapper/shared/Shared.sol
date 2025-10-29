// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "test/Base.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {MorphoMarket} from "contracts/markets/MorphoMarket.sol";

// Interfaces
import {Mainnet} from "src/contracts/utils/Addresses.sol";

abstract contract Fork_Shared_Test is Base_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();

        // Generate a fork
        _createAndSelectFork();

        // Deploy Mock contracts
        _deployMockContracts();

        // Generate addresses
        _generateAddresses();

        // Deploy contracts
        _deployContracts();

        // Label contracts
        labelAll();
    }

    function _createAndSelectFork() internal {
        // Check if the PROVIDER_URL is set.
        require(vm.envExists("PROVIDER_URL"), "PROVIDER_URL not set");

        // Create and select a fork at specific block number, because we are testing MerkleProofs
        vm.createSelectFork("mainnet", 23_681_964);
    }

    function _deployMockContracts() internal {}

    function _generateAddresses() internal {
        morpho = IERC20(Mainnet.MORPHO);
    }

    function _deployContracts() internal {
        // --- Deploy MorphoMarket Proxy ---
        // Use the already existing address for the MorphoMarket Proxy, because we need to match the Merkle root.
        address targetedAddress = 0x29c4Bb7B1eBcc53e8CBd16480B5bAe52C69806D3;
        // Deploy Proxy contract for the MorphoMarket.
        deployCodeTo("Proxy.sol", targetedAddress);
        morphoMarketProxy = Proxy(payable(targetedAddress));

        // --- Deploy MorphoMarket implementation ---
        // Deploy MorphoMarket implementation.
        MorphoMarket morphoMarketImpl = new MorphoMarket(address(0), targetedAddress);

        // Initialize Proxy with MorphoMarket implementation.
        morphoMarketProxy.upgradeTo(address(morphoMarketImpl));

        // Set the Proxy as the MorphoMarket.
        morphoMarket = MorphoMarket(address(morphoMarketProxy));

        // Set harvester and merkle distributor
        morphoMarket.setHarvester(address(this));
        morphoMarket.setMerkleDistributor(Mainnet.MORPHO_MERKLE_DISTRIBUTOR);
    }
}
