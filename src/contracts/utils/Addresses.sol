// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console} from "forge-std/console.sol";

library Common {
    address public constant ZERO = address(0);
}

library Mainnet {
    // Governance
    address public constant TIMELOCK = 0x35918cDE7233F2dD33fA41ae3Cb6aE0e42E0e69F;
    address public constant GOVERNOR_FIVE = 0x3cdD07c16614059e66344a7b579DAB4f9516C0b6;
    address public constant GOVERNOR_SIX = 0x1D3Fbd4d129Ddd2372EA85c5Fa00b2682081c9EC;
    address public constant STRATEGIST = 0x4FF1b9D9ba8558F5EAfCec096318eA0d8b541971;
    address public constant TREASURY = 0x70fCE97d671E81080CA3ab4cc7A59aAc2E117137;

    // Multisig and EOAs
    address public constant INITIAL_DEPLOYER = address(0x1001);
    address public constant GOV_MULTISIG = 0xbe2AB3d3d8F6a32b96414ebbd865dBD276d3d899;
    address public constant ARM_MULTISIG = 0xC8F2cF4742C86295653f893214725813B16f7410;
    address public constant OETH_RELAYER = 0x4b91827516f79d6F6a1F292eD99671663b09169a;
    address public constant ARM_RELAYER = 0x39878253374355DBcc15C86458F084fb6f2d6DE7;

    // Tokens
    address public constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    // Contracts
    address public constant OETH_VAULT = 0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab;
    address public constant OETH_ARM = 0x6bac785889A4127dB0e0CeFEE88E0a9F1Aaf3cC7;
    address public constant LIDO_ARM = 0x85B78AcA6Deae198fBF201c82DAF6Ca21942acc6;
    address public constant ARM_BUYBACK = 0xBa0E6d6ea72cDc0D6f9fCdcc04147c671BA83dB5;

    // Lido
    address public constant LIDO_WITHDRAWAL = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
    address public constant LIDO_EL_VAULT = 0x388C818CA8B9251b393131C08a736A67ccB19297;
    address public constant LIDO_WITHDRAWAL_MANAGER = 0xB9D7934878B5FB9610B3fE8A5e441e8fad7E293f;
}

library Holesky {
    // Multisig and EOAs
    address public constant INITIAL_DEPLOYER = 0x1b94CA50D3Ad9f8368851F8526132272d1a5028C;
    address public constant RELAYER = 0x3C6B0c7835a2E2E0A45889F64DcE4ee14c1D5CB4;

    // Tokens
    address public constant OETH = 0xB1876706d2402d300bf263F9e53335CEFc53d9Cb;
    address public constant WETH = 0x94373a4919B3240D86eA41593D5eBa789FEF3848;

    // Contracts
    address public constant OETH_VAULT = 0x19d2bAaBA949eFfa163bFB9efB53ed8701aA5dD9;
    address public constant OETH_ARM = 0x8c7a302e208885ee4658E7422f9E259364cC993b;
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
        resolver[MAINNET]["OPERATOR"] = Mainnet.OETH_RELAYER;

        // Tokens
        resolver[MAINNET]["OETH"] = Mainnet.OETH;
        resolver[MAINNET]["WETH"] = Mainnet.WETH;
        resolver[MAINNET]["STETH"] = Mainnet.STETH;
        resolver[MAINNET]["WSTETH"] = Mainnet.WSTETH;

        // Contracts
        resolver[MAINNET]["OETH_VAULT"] = Mainnet.OETH_VAULT;
        resolver[MAINNET]["OETH_ARM"] = Mainnet.OETH_ARM;
        resolver[MAINNET]["LIDO_ARM"] = Mainnet.LIDO_ARM;

        // Test accounts
        resolver[MAINNET]["INITIAL_DEPLOYER"] = address(0x1001);
        resolver[MAINNET]["WHALE_OETH"] = 0x8E02247D3eE0E6153495c971FFd45Aa131f4D7cB;

        ///// Holesky //////
        // Governance
        resolver[HOLESKY]["GOVERNOR"] = Holesky.RELAYER;
        resolver[HOLESKY]["OPERATOR"] = Holesky.RELAYER;

        // Tokens
        resolver[HOLESKY]["OETH"] = Holesky.OETH;
        resolver[HOLESKY]["WETH"] = Holesky.WETH;

        // Contracts
        resolver[HOLESKY]["OETH_VAULT"] = Holesky.OETH_VAULT;
        resolver[HOLESKY]["OETH_ARM"] = Mainnet.OETH_ARM;

        // Test accounts
        resolver[HOLESKY]["INITIAL_DEPLOYER"] = Holesky.INITIAL_DEPLOYER;
    }

    function resolve(string memory name) public view returns (address resolved) {
        uint256 chainId = block.chainid == 31337 ? 1 : block.chainid;
        resolved = resolver[chainId][name];

        if (resolved == address(0)) {
            console.log("Failed to resolve address for %s on chain %d", name, chainId);
            revert UnresolvedAddress(chainId, name);
        }

        // console.log("Resolve %s on chain %d to %s", name, chainId, resolved);
    }
}
