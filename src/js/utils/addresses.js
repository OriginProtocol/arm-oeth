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
addresses.mainnet.stETH = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84";
addresses.mainnet.wstETH = "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0";

addresses.mainnet.OethARM = "0x6bac785889A4127dB0e0CeFEE88E0a9F1Aaf3cC7";
addresses.mainnet.lidoARM = "0x85B78AcA6Deae198fBF201c82DAF6Ca21942acc6";

// Lido
addresses.mainnet.lidoWithdrawalQueue =
  "0x889edc2edab5f40e902b864ad4d7ade8e412f9b1";
addresses.mainnet.lidoExecutionLayerVault =
  "0x388C818CA8B9251b393131C08a736A67ccB19297";
addresses.mainnet.lidoWithdrawalManager =
  "0xB9D7934878B5FB9610B3fE8A5e441e8fad7E293f";

// AMMs
addresses.mainnet.CurveStEthPool = "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022";
addresses.mainnet.CurveNgStEthPool =
  "0x21e27a5e5513d6e65c4f830167390997aa84843a";
addresses.mainnet.UniswapV3Quoter =
  "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6";
addresses.mainnet.UniswapV3stETHWETHPool =
  "0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa";

// Sonic
addresses.sonic = {};
addresses.mainnet.WS = "0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38";
addresses.mainnet.SILO = "0x53f753E4B17F4075D6fa2c6909033d224b81e698";

module.exports = addresses;
