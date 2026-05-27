const { Contract, ZeroAddress, parseUnits } = require("ethers");

const addresses = require("./addresses");
const { parseAddress } = require("./addressParser");

const MAX_SWAP_LIQUIDITY = (1n << 128n) - 1n;

const ARM_BASES = {
  Lido: { defaultBase: "STETH", liquidity: "WETH" },
  EtherFi: { defaultBase: "EETH", liquidity: "WETH" },
  Ethena: { defaultBase: "SUSDE", liquidity: "USDE" },
  Oeth: { defaultBase: "OETH", liquidity: "WETH" },
  Origin: { defaultBase: "OS", liquidity: "WS" },
};

const BASE_ALIASES = {
  STETH: "STETH",
  WSTETH: "WSTETH",
  EETH: "EETH",
  WEETH: "WEETH",
  SUSDE: "SUSDE",
  OETH: "OETH",
  WOETH: "WOETH",
  OS: "OS",
  WOS: "WOS",
};

const normalizeBaseSymbol = (base) => {
  if (!base) return undefined;
  const normalized = base.toString().replace(/-/g, "").toUpperCase();
  const symbol = BASE_ALIASES[normalized];
  if (!symbol) throw new Error(`Unsupported base asset ${base}`);
  return symbol;
};

const defaultBaseSymbol = (armName) => {
  const config = ARM_BASES[armName];
  if (!config) throw new Error(`Unsupported ARM ${armName}`);
  return config.defaultBase;
};

const liquiditySymbol = (armName) => {
  const config = ARM_BASES[armName];
  if (!config) throw new Error(`Unsupported ARM ${armName}`);
  return config.liquidity;
};

const resolveAssetAddress = async (symbol) => {
  const address = {
    STETH: addresses.mainnet.stETH,
    WSTETH: addresses.mainnet.wstETH,
    EETH: addresses.mainnet.eETH,
    WEETH: addresses.mainnet.weETH,
    SUSDE: addresses.mainnet.sUSDe,
    OETH: addresses.mainnet.OETHProxy,
    WOETH: addresses.mainnet.WOETH,
    OS: addresses.sonic.OSonicProxy,
    WOS: addresses.sonic.WOS,
    WETH: addresses.mainnet.WETH,
    USDE: addresses.mainnet.USDe,
    WS: addresses.sonic.WS,
  }[symbol];

  return address ?? parseAddress(symbol);
};

const parseSwapCap = (amount) => {
  if (amount === undefined || amount === null) return MAX_SWAP_LIQUIDITY;
  if (typeof amount === "bigint") return amount;
  if (typeof amount === "number") return parseUnits(amount.toString(), 18);
  const value = amount.toString();
  return value.includes(".") ? parseUnits(value, 18) : BigInt(value);
};

const toConfigObject = (config) => ({
  buyPrice: config.buyPrice ?? config[0],
  sellPrice: config.sellPrice ?? config[1],
  buyLiquidityRemaining: config.buyLiquidityRemaining ?? config[2],
  sellLiquidityRemaining: config.sellLiquidityRemaining ?? config[3],
  crossPrice: config.crossPrice ?? config[4],
  pendingRedeemAssets: config.pendingRedeemAssets ?? config[5],
  peggedToLiquidityAsset: config.peggedToLiquidityAsset ?? config[6],
  adapter: config.adapter ?? config[7],
});

const resolveArmBase = async ({ arm, armName, base, blockTag }) => {
  const baseSymbol = normalizeBaseSymbol(base) ?? defaultBaseSymbol(armName);
  const baseAddress = await resolveAssetAddress(baseSymbol);
  const liquidityAddress = await arm.liquidityAsset({ blockTag });
  const config = toConfigObject(
    await arm.baseAssetConfigs(baseAddress, { blockTag }),
  );

  if (config.adapter === ZeroAddress) {
    throw new Error(`${baseSymbol} is not configured on ${armName} ARM`);
  }

  return {
    baseSymbol,
    baseAddress,
    liquidityAddress,
    config,
  };
};

const adapterContract = async (adapterAddress, signerOrProvider) =>
  new Contract(
    adapterAddress,
    [
      "function convertToAssets(uint256) view returns (uint256)",
      "function convertToShares(uint256) view returns (uint256)",
      "function requestShares(uint256) view returns (uint256)",
      "function requestAssets(uint256) view returns (uint256)",
      "function pendingRequestIdsLength() view returns (uint256)",
      "function pendingRequestId(uint256) view returns (uint256)",
      "function claimableRedeem() view returns (uint256,uint256)",
      "function lastRequestTimestamp() view returns (uint32)",
      "function DELAY_REQUEST() view returns (uint256)",
      "function totalRequests() view returns (uint256)",
      "function unstakerIndexAt(uint256) view returns (uint8)",
      "function unstakers(uint256) view returns (address)",
      "function requestShares(address) view returns (uint256)",
      "function requestAssets(address) view returns (uint256)",
    ],
    signerOrProvider,
  );

module.exports = {
  MAX_SWAP_LIQUIDITY,
  adapterContract,
  defaultBaseSymbol,
  liquiditySymbol,
  normalizeBaseSymbol,
  parseSwapCap,
  resolveArmBase,
  resolveAssetAddress,
  toConfigObject,
};
