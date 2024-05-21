/* IMPORTANT these are duplicated in `dapp/src/constants/contractAddresses` changes here should
 * also be done there.
 */

const addresses = {};

// Utility addresses
addresses.zero = "0x0000000000000000000000000000000000000000";
addresses.dead = "0x0000000000000000000000000000000000000001";
addresses.ETH = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

addresses.mainnet = {};

// Native stablecoins
addresses.mainnet.DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
addresses.mainnet.USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
addresses.mainnet.USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
addresses.mainnet.TUSD = "0x0000000000085d4780B73119b644AE5ecd22b376";
addresses.mainnet.LUSD = "0x5f98805A4E8be255a32880FDeC7F6728C6568bA0";

// AAVE
addresses.mainnet.Aave = "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9"; // v1-v2
addresses.mainnet.aTUSD = "--"; // Todo: use v2
addresses.mainnet.aUSDT = "0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811"; // v2
addresses.mainnet.aDAI = "0x028171bca77440897b824ca71d1c56cac55b68a3"; // v2
addresses.mainnet.aUSDC = "0xBcca60bB61934080951369a648Fb03DF4F96263C"; // v2
addresses.mainnet.aWETH = "0x030ba81f1c18d280636f32af80b9aad02cf0854e"; // v2

// Compound
addresses.mainnet.COMP = "0xc00e94Cb662C3520282E6f5717214004A7f26888";
addresses.mainnet.cDAI = "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643";
addresses.mainnet.cUSDC = "0x39aa39c021dfbae8fac545936693ac917d5e7563";
addresses.mainnet.cUSDT = "0xf650c3d88d12db855b8bf7d11be6c55a4e07dcc9";
// Curve
addresses.mainnet.CRV = "0xd533a949740bb3306d119cc777fa900ba034cd52";
addresses.mainnet.ThreePoolToken = "0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490";
addresses.mainnet.CurveStEthPool = "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022";
addresses.mainnet.CurveNgStEthPool =
  "0x21e27a5e5513d6e65c4f830167390997aa84843a";
// CVX
addresses.mainnet.CVX = "0x4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b";

// Maker Dai Savings Rate
addresses.mainnet.sDAI = "0x83F20F44975D03b1b09e64809B757c47f942BEeA";

// Origin
addresses.mainnet.OGN = "0x8207c1ffc5b6804f6024322ccf34f29c3541ae26";
addresses.mainnet.OGV = "0x9c354503C38481a7A7a51629142963F98eCC12D0";
addresses.mainnet.veOGV = "0x0C4576Ca1c365868E162554AF8e385dc3e7C66D9";

// OETH
addresses.mainnet.OETHProxy = "0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3";
addresses.mainnet.WOETHProxy = "0xDcEe70654261AF21C44c093C300eD3Bb97b78192";
addresses.mainnet.OETHVaultProxy = "0x39254033945aa2e4809cc2977e7087bee48bd7ab";
addresses.mainnet.OETHZapper = "0x9858e47BCbBe6fBAC040519B02d7cd4B2C470C66";

// OETH Tokens
addresses.mainnet.WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
addresses.mainnet.sfrxETH = "0xac3E018457B222d93114458476f3E3416Abbe38F";
addresses.mainnet.frxETH = "0x5E8422345238F34275888049021821E8E08CAa1f";
addresses.mainnet.rETH = "0xae78736Cd615f374D3085123A210448E74Fc6393";
addresses.mainnet.stETH = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84";
addresses.mainnet.wstETH = "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0";

// Balancer
addresses.mainnet.BAL = "0xba100000625a3754423978a60c9317c58a424e3D";

// Aura
addresses.mainnet.AURA = "0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF";

// Flux Strategy
addresses.mainnet.fDAI = "0xe2bA8693cE7474900A045757fe0efCa900F6530b";
addresses.mainnet.fUSDC = "0x465a5a630482f3abD6d3b84B39B29b07214d19e5";
addresses.mainnet.fUSDT = "0x81994b9607e06ab3d5cF3AffF9a67374f05F27d7";

// Origin Ether ARM
addresses.mainnet.OEthARM = "";
addresses.mainnet.OETHVault = "0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab";

// Uniswap
addresses.mainnet.UniswapV3Quoter =
  "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6";
addresses.mainnet.UniswapV3stETHWETHPool =
  "0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa";
addresses.mainnet.UniswapV3StaticOracle =
  "0xB210CE856631EeEB767eFa666EC7C1C57738d438";

module.exports = addresses;
