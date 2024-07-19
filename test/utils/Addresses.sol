// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library Mainnet {
    //////////////////////////////////////////////////////
    /// --- EOA
    //////////////////////////////////////////////////////
    address public constant NULL = address(0);
    address public constant STRATEGIST = 0xF14BBdf064E3F67f51cd9BD646aE3716aD938FDC;
    address public constant WHALE_OETH = 0x8E02247D3eE0E6153495c971FFd45Aa131f4D7cB;

    //////////////////////////////////////////////////////
    /// --- CONTRACTS
    //////////////////////////////////////////////////////
    address public constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant TIMELOCK = 0x35918cDE7233F2dD33fA41ae3Cb6aE0e42E0e69F;
    address public constant OETHVAULT = 0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab;
}
