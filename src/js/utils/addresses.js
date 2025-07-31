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
addresses.mainnet.FluidDexResolver = 
  "0x71783F64719899319B56BdA4F27E1219d9AF9a3d";
addresses.mainnet.FluidWstEthEthPool =
  "0x0B1a513ee24972DAEf112bC777a5610d4325C9e7";

// Sonic
addresses.sonic = {};
addresses.sonic.guardian = "0x63cdd3072F25664eeC6FAEFf6dAeB668Ea4de94a";
addresses.sonic.WS = "0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38";
addresses.sonic.OriginARM = "0x2F872623d1E1Af5835b08b0E49aAd2d81d649D30";
addresses.sonic.SILO = "0xb098AFC30FCE67f1926e735Db6fDadFE433E61db";
addresses.sonic.OSonicProxy = "0xb1e25689D55734FD3ffFc939c4C3Eb52DFf8A794";
addresses.sonic.OSonicVaultProxy = "0xa3c0eCA00D2B76b4d1F170b0AB3FdeA16C180186";
addresses.sonic.siloVarlamoreMarket =
  "0x248Dbbc31F2D7675775DB4A9308a98444DaBaECf";
addresses.sonic.harvester = "0x08876C0F5a80c1a43A6396b13A881A26F4b6Adfe";

module.exports = addresses;
