// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/console.sol";

library Common {
    address public constant ZERO = address(0);
}

library Mainnet {
    // Governance
    address public constant TIMELOCK = 0x35918cDE7233F2dD33fA41ae3Cb6aE0e42E0e69F;
    address public constant GOVERNOR_FIVE = 0x3cdD07c16614059e66344a7b579DAB4f9516C0b6;
    address public constant GOVERNOR_SIX = 0x1D3Fbd4d129Ddd2372EA85c5Fa00b2682081c9EC;

    // Multisig and EOAs
    address public constant INITIAL_DEPLOYER = address(0x1001);
    address public constant STRATEGIST = 0xF14BBdf064E3F67f51cd9BD646aE3716aD938FDC;
    address public constant GOV_MULTISIG = 0xbe2AB3d3d8F6a32b96414ebbd865dBD276d3d899;

    // Tokens
    address public constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Contracts
    address public constant OETH_VAULT = 0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab;
    address public constant OETH_ARM = 0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b;
}

library Holesky {
    // Multisig and EOAs
    address public constant INITIAL_DEPLOYER = 0x1b94CA50D3Ad9f8368851F8526132272d1a5028C;

    // Tokens
    address public constant OETH = 0xB1876706d2402d300bf263F9e53335CEFc53d9Cb;
    address public constant WETH = 0x94373a4919B3240D86eA41593D5eBa789FEF3848;

    // Contracts
    address public constant OETH_VAULT = 0x19d2bAaBA949eFfa163bFB9efB53ed8701aA5dD9;
}

contract AddressResolver {
    // Chain ids of different networks
    uint256 public constant MAINNET = 1;
    uint256 public constant HOLESKY = 17000;
    uint256 public constant BASE = 8453;
    uint256 public constant ARBITRUM = 42161;

    mapping(uint256 => mapping(string => address)) internal resolver;

    error UnresolvedAddress(uint256 chainId, string name);

    constructor() {
        ///// Mainnet //////

        // Governance
        resolver[MAINNET]["GOVERNOR"] = Mainnet.TIMELOCK;
        resolver[MAINNET]["GOVERNANCE"] = Mainnet.GOVERNOR_SIX;
        resolver[MAINNET]["GOV_MULTISIG"] = Mainnet.GOV_MULTISIG;
        resolver[MAINNET]["STRATEGIST"] = Mainnet.STRATEGIST;

        // Tokens
        resolver[MAINNET]["OETH"] = Mainnet.OETH;
        resolver[MAINNET]["WETH"] = Mainnet.WETH;

        // Contracts
        resolver[MAINNET]["OETH_VAULT"] = Mainnet.OETH_VAULT;
        resolver[MAINNET]["OETH_ARM"] = Mainnet.OETH_ARM;

        // Test accounts
        resolver[MAINNET]["INITIAL_DEPLOYER"] = address(0x1001);
        resolver[MAINNET]["WHALE_OETH"] = 0x8E02247D3eE0E6153495c971FFd45Aa131f4D7cB;

        ///// Holesky //////
        // Governance
        resolver[HOLESKY]["STRATEGIST"] = Holesky.INITIAL_DEPLOYER;
        resolver[HOLESKY]["GOVERNOR"] = Holesky.INITIAL_DEPLOYER;

        // Tokens
        resolver[HOLESKY]["OETH"] = Holesky.OETH;
        resolver[HOLESKY]["WETH"] = Holesky.WETH;

        // Contracts
        resolver[HOLESKY]["OETH_VAULT"] = Holesky.OETH_VAULT;

        // Test accounts
        resolver[HOLESKY]["INITIAL_DEPLOYER"] = Holesky.INITIAL_DEPLOYER;
    }

    function resolve(string memory name) public view returns (address resolved) {
        resolved = resolver[block.chainid][name];

        if (resolved == address(0)) {
            console.log("Failed to resolve address for %s on chain %d", name, block.chainid);
            revert UnresolvedAddress(block.chainid, name);
        }

        // console.log("Resolve %s on chain %d to %s", name, block.chainid, resolved);
    }
}
