/* IMPORTANT these are duplicated in `dapp/src/constants/contractAddresses` changes here should
 * also be done there.
 */

const addresses = {};

// Utility addresses
addresses.zero = "0x0000000000000000000000000000000000000000";
addresses.dead = "0x0000000000000000000000000000000000000001";
addresses.ETH = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

addresses.mainnet = {};

// OETH
addresses.mainnet.OETHProxy = "0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3";
addresses.mainnet.OETHVaultProxy = "0x39254033945aa2e4809cc2977e7087bee48bd7ab";

// Tokens
addresses.mainnet.WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

// Origin Ether ARM
addresses.mainnet.OEthARM = "";
addresses.mainnet.OETHVault = "0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab";

module.exports = addresses;
