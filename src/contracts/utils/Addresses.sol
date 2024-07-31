// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library Common {
    address public constant NULL = address(0);
}

library Mainnet {
    address public constant TIMELOCK = 0x35918cDE7233F2dD33fA41ae3Cb6aE0e42E0e69F;
    address public constant GOVERNOR_FIVE = 0x3cdD07c16614059e66344a7b579DAB4f9516C0b6;
    address public constant GOVERNOR_SIX = 0x1D3Fbd4d129Ddd2372EA85c5Fa00b2682081c9EC;

    address public constant STRATEGIST = 0xF14BBdf064E3F67f51cd9BD646aE3716aD938FDC;
    address public constant GOV_MULTISIG = 0xbe2AB3d3d8F6a32b96414ebbd865dBD276d3d899;

    address public constant INITIAL_DEPLOYER = address(0x1001);

    address public constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public constant WHALE_OETH = 0x8E02247D3eE0E6153495c971FFd45Aa131f4D7cB;

    address public constant OETH_VAULT = 0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab;
    address public constant OETH_ARM = 0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b;
}

library Holesky {
    address public constant STRATEGIST = 0x1b94CA50D3Ad9f8368851F8526132272d1a5028C;
    address public constant GOVERNOR = 0x1b94CA50D3Ad9f8368851F8526132272d1a5028C;

    address public constant INITIAL_DEPLOYER = 0x1b94CA50D3Ad9f8368851F8526132272d1a5028C;

    address public constant OETH = 0xB1876706d2402d300bf263F9e53335CEFc53d9Cb;
    address public constant WETH = 0x94373a4919B3240D86eA41593D5eBa789FEF3848;

    address public constant OETH_VAULT = 0x19d2bAaBA949eFfa163bFB9efB53ed8701aA5dD9;
}
