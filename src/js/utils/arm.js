const { Contract, ZeroAddress, parseUnits } = require("ethers");

const addresses = require("./addresses");
const { parseAddress } = require("./addressParser");

const MAX_SWAP_LIQUIDITY = (1n << 128n) - 1n;
const PRICE_SCALE = parseUnits("1", 36);

const LEGACY_ARM_ABI = [
  "function activeMarket() view returns (address)",
  "function allocate() returns (int256)",
  "function armBuffer() view returns (uint256)",
  "function withdrawsQueued() view returns (uint256)",
  "function withdrawsClaimed() view returns (uint256)",
  "function baseAsset() view returns (address)",
  "function DELAY_REQUEST() view returns (uint256)",
  "function claimEtherFiWithdrawals(uint256[])",
  "function claimBaseWithdrawals(uint8)",
  "function claimLidoWithdrawals(uint256[],uint256[])",
  "function claimOriginWithdrawals(uint256[]) returns (uint256)",
  "function crossPrice() view returns (uint256)",
  "function etherfiWithdrawalQueueAmount() view returns (uint256)",
  "function lidoWithdrawalQueueAmount() view returns (uint256)",
  "function liquidityAsset() view returns (address)",
  "function lastRequestTimestamp() view returns (uint32)",
  "function requestEtherFiWithdrawal(uint256) returns (uint256)",
  "function requestBaseWithdrawal(uint256)",
  "function requestLidoWithdrawals(uint256[]) returns (uint256[])",
  "function requestOriginWithdrawal(uint256) returns (uint256)",
  "function setARMBuffer(uint256)",
  "function setPrices(uint256,uint256)",
  "function traderate0() view returns (uint256)",
  "function traderate1() view returns (uint256)",
  "function unstakers(uint256) view returns (address)",
  "function vaultWithdrawalAmount() view returns (uint256)",
];

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

const assetAddressesBySymbol = () => ({
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
});

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
  const address = assetAddressesBySymbol()[symbol];

  return address ?? parseAddress(symbol);
};

const symbolForAddress = async (address) => {
  const lowerAddress = address.toLowerCase();
  for (const [symbol, knownAddress] of Object.entries(
    assetAddressesBySymbol(),
  )) {
    if (knownAddress?.toLowerCase() === lowerAddress) return symbol;
  }
  return address;
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

const callOptional = async (contract, fn, args = [], fallback = 0n) => {
  if (!contract[fn]) return fallback;
  try {
    return await contract[fn](...args);
  } catch {
    return fallback;
  }
};

const isMissingSelectorError = (err) =>
  (err instanceof TypeError && err.message.includes("is not a function")) ||
  err?.code === "BAD_DATA" ||
  err?.code === "CALL_EXCEPTION" ||
  err?.data === "0x" ||
  err?.info?.error?.data === "0x";

const isMissingSelectorOrBareRevertError = (err) =>
  isMissingSelectorError(err) ||
  (err?.name === "ProviderError" && err?.message === "execution reverted");

const errorSummary = (err) =>
  [err?.name, err?.code, err?.message, err?.data || err?.info?.error?.data]
    .filter(Boolean)
    .join(": ");

const legacyArmContract = async (arm, signerOrProvider) =>
  new Contract(
    await arm.getAddress(),
    LEGACY_ARM_ABI,
    signerOrProvider ?? arm.runner,
  );

const legacyPendingRedeemAssets = async (legacyArm, armName, blockTag) => {
  const opts = blockTag === undefined ? [] : [{ blockTag }];
  if (armName === "Lido") {
    return callOptional(legacyArm, "lidoWithdrawalQueueAmount", opts);
  }
  if (armName === "EtherFi") {
    return callOptional(legacyArm, "etherfiWithdrawalQueueAmount", opts);
  }
  if (armName === "Oeth" || armName === "Origin") {
    return callOptional(legacyArm, "vaultWithdrawalAmount", opts);
  }
  return 0n;
};

const resolveLegacyArmBase = async ({
  arm,
  armName,
  requestedBaseSymbol,
  requestedBaseAddress,
  blockTag,
}) => {
  const legacyArm = await legacyArmContract(arm);
  const callOpts = blockTag === undefined ? [] : [{ blockTag }];
  const [
    legacyBaseAddress,
    liquidityAddress,
    traderate0,
    buyPrice,
    crossPrice,
  ] = await Promise.all([
    legacyArm.baseAsset(...callOpts),
    legacyArm.liquidityAsset(...callOpts),
    legacyArm.traderate0(...callOpts),
    legacyArm.traderate1(...callOpts),
    legacyArm.crossPrice(...callOpts),
  ]);

  if (
    requestedBaseAddress &&
    requestedBaseAddress.toLowerCase() !== legacyBaseAddress.toLowerCase()
  ) {
    const legacyBaseSymbol = await symbolForAddress(legacyBaseAddress);
    throw new Error(
      `Legacy ${armName} ARM only supports ${legacyBaseSymbol} as its base asset`,
    );
  }

  const baseSymbol =
    requestedBaseSymbol ?? (await symbolForAddress(legacyBaseAddress));
  const pendingRedeemAssets = await legacyPendingRedeemAssets(
    legacyArm,
    armName,
    blockTag,
  );

  return {
    version: "legacy",
    armName,
    arm,
    compatibleArm: legacyArm,
    baseSymbol,
    baseAddress: legacyBaseAddress,
    liquidityAddress,
    config: {
      buyPrice,
      sellPrice: (PRICE_SCALE * PRICE_SCALE) / traderate0,
      buyLiquidityRemaining: MAX_SWAP_LIQUIDITY,
      sellLiquidityRemaining: MAX_SWAP_LIQUIDITY,
      crossPrice,
      pendingRedeemAssets,
      peggedToLiquidityAsset: armName !== "Ethena",
      adapter: ZeroAddress,
    },
  };
};

const resolveArmBase = async ({ arm, armName, base, blockTag }) => {
  const requestedBaseSymbol = normalizeBaseSymbol(base);
  const baseSymbol = requestedBaseSymbol ?? defaultBaseSymbol(armName);
  const baseAddress = await resolveAssetAddress(baseSymbol);

  let liquidityAddress;
  let config;
  try {
    liquidityAddress = await arm.liquidityAsset({ blockTag });
    config = toConfigObject(
      await arm.baseAssetConfigs(baseAddress, { blockTag }),
    );
  } catch {
    // baseAssetConfigs is a public mapping on the multiBase ARM and never
    // reverts, so any failure reading it means this is a legacy single-asset
    // ARM (the selector is absent on-chain). Some RPCs surface that as a bare
    // "execution reverted" with no decodable data rather than a recognizable
    // missing-selector error, so fall back unconditionally instead of
    // pattern-matching the error shape.
    return resolveLegacyArmBase({
      arm,
      armName,
      requestedBaseSymbol,
      requestedBaseAddress: requestedBaseSymbol ? baseAddress : undefined,
      blockTag,
    });
  }

  if (config.adapter === ZeroAddress) {
    throw new Error(`${baseSymbol} is not configured on ${armName} ARM`);
  }

  return {
    version: "multiBase",
    armName,
    arm,
    compatibleArm: arm,
    baseSymbol,
    baseAddress,
    liquidityAddress,
    config,
  };
};

const setArmPrices = async ({
  baseContext,
  signer,
  buyPrice,
  sellPrice,
  buyAmount,
  sellAmount,
}) => {
  if (baseContext.version === "legacy") {
    // Legacy single-asset ARMs only expose setPrices(buyPrice, sellPrice).
    // They have no per-price liquidity limits, so buyAmount/sellAmount are dropped.
    return baseContext.compatibleArm
      .connect(signer)
      .setPrices(buyPrice, sellPrice);
  }

  return baseContext.arm
    .connect(signer)
    .setPrices(
      baseContext.baseAddress,
      buyPrice,
      sellPrice,
      buyAmount,
      sellAmount,
    );
};

const requestBaseAssetWithdrawal = async ({
  baseContext,
  signer,
  amount,
  maxAmount,
}) => {
  if (baseContext.version !== "legacy") {
    return baseContext.arm
      .connect(signer)
      .requestBaseAssetRedeem(baseContext.baseAddress, amount);
  }

  const legacyArm = baseContext.compatibleArm.connect(signer);
  if (baseContext.armName === "Lido" || baseContext.baseSymbol === "STETH") {
    const maxRequestAmount =
      maxAmount === undefined ? amount : parseUnits(maxAmount.toString(), 18);
    const requestAmounts = [];
    let remainingAmount = amount;
    while (remainingAmount > 0n) {
      const requestAmount =
        remainingAmount > maxRequestAmount ? maxRequestAmount : remainingAmount;
      requestAmounts.push(requestAmount);
      remainingAmount -= requestAmount;
    }
    return legacyArm.requestLidoWithdrawals(requestAmounts);
  }
  if (baseContext.armName === "EtherFi") {
    return legacyArm.requestEtherFiWithdrawal(amount);
  }
  if (baseContext.armName === "Oeth" || baseContext.armName === "Origin") {
    return legacyArm.requestOriginWithdrawal(amount);
  }
  if (baseContext.armName === "Ethena") {
    return legacyArm.requestBaseWithdrawal(amount);
  }

  throw new Error(
    `Legacy ${baseContext.armName} ARM withdrawals are unsupported`,
  );
};

const claimBaseAssetWithdrawal = async ({
  baseContext,
  signer,
  shares,
  requestIds,
  hintIds,
  unstakerIndex,
}) => {
  if (baseContext.version !== "legacy") {
    return baseContext.arm
      .connect(signer)
      .claimBaseAssetRedeem(baseContext.baseAddress, shares);
  }

  const legacyArm = baseContext.compatibleArm.connect(signer);
  if (baseContext.armName === "Lido" || baseContext.baseSymbol === "STETH") {
    return legacyArm.claimLidoWithdrawals(requestIds, hintIds);
  }
  if (baseContext.armName === "EtherFi") {
    return legacyArm.claimEtherFiWithdrawals(requestIds);
  }
  if (baseContext.armName === "Oeth" || baseContext.armName === "Origin") {
    return legacyArm.claimOriginWithdrawals(requestIds);
  }
  if (baseContext.armName === "Ethena") {
    return legacyArm.claimBaseWithdrawals(unstakerIndex);
  }

  throw new Error(`Legacy ${baseContext.armName} ARM claims are unsupported`);
};

const staticCallAllocate = async (arm) => {
  try {
    const result = await arm.allocate.staticCall();
    return Array.isArray(result) ? result[1] : result;
  } catch (err) {
    if (!isMissingSelectorError(err)) throw err;
    const legacyArm = await legacyArmContract(arm);
    return legacyArm.allocate.staticCall();
  }
};

const estimateAllocateGas = async (arm, signer) => {
  try {
    return await arm.connect(signer).allocate.estimateGas();
  } catch (err) {
    if (!isMissingSelectorError(err)) throw err;
    const legacyArm = await legacyArmContract(arm, signer);
    return legacyArm.allocate.estimateGas();
  }
};

const callAllocate = async (arm, signer, overrides = {}) => {
  try {
    return await arm.connect(signer).allocate(overrides);
  } catch (err) {
    if (!isMissingSelectorError(err)) throw err;
    const legacyArm = await legacyArmContract(arm, signer);
    return legacyArm.allocate(overrides);
  }
};

const getArmBuffer = async (arm, blockTag) => {
  try {
    return await arm.armBuffer({ blockTag });
  } catch (err) {
    if (!isMissingSelectorError(err)) throw err;
    const legacyArm = await legacyArmContract(arm);
    try {
      return await legacyArm.armBuffer({ blockTag });
    } catch {
      throw new Error("ARM does not expose armBuffer()");
    }
  }
};

const getOutstandingWithdrawals = async (arm, blockTag) => {
  const opts = blockTag === undefined ? [] : [{ blockTag }];
  let reservedWithdrawLiquidityError;
  let currentAbiWithdrawalsError;
  // Liquidity reserved for outstanding LP withdrawal requests (asset-denominated).
  // Newer ARMs track the asset-denominated amount directly in
  // reservedWithdrawLiquidity(). Legacy Lido and EtherFi ARMs expose
  // withdrawsQueued()/withdrawsClaimed(); several new ABIs dropped these getters
  // even though the deployed legacy contracts still implement them on-chain, so
  // fall back to the legacy ABI.
  if (arm.reservedWithdrawLiquidity) {
    try {
      return await arm.reservedWithdrawLiquidity(...opts);
    } catch (err) {
      reservedWithdrawLiquidityError = err;
      if (!isMissingSelectorOrBareRevertError(err)) {
        throw new Error(
          `Failed to read outstanding withdrawals via reservedWithdrawLiquidity(): ${errorSummary(err)}`,
          { cause: err },
        );
      }
    }
  }

  try {
    const [queued, claimed] = await Promise.all([
      arm.withdrawsQueued(...opts),
      arm.withdrawsClaimed(...opts),
    ]);
    return queued - claimed;
  } catch (err) {
    currentAbiWithdrawalsError = err;
    if (!isMissingSelectorError(err)) {
      throw new Error(
        `Failed to read outstanding withdrawals via withdrawsQueued()/withdrawsClaimed(): ${errorSummary(err)}`,
        { cause: err },
      );
    }
  }
  try {
    const legacyArm = await legacyArmContract(arm);
    const [queued, claimed] = await Promise.all([
      legacyArm.withdrawsQueued(...opts),
      legacyArm.withdrawsClaimed(...opts),
    ]);
    return queued - claimed;
  } catch (err) {
    if (!isMissingSelectorError(err)) {
      throw new Error(
        `Failed to read outstanding withdrawals via legacy withdrawsQueued()/withdrawsClaimed(): ${errorSummary(err)}`,
        { cause: err },
      );
    }

    const armAddress = await arm.getAddress();
    const reservedResult = reservedWithdrawLiquidityError
      ? `failed (${errorSummary(reservedWithdrawLiquidityError)})`
      : "was not available in the current ABI";
    const currentAbiResult = currentAbiWithdrawalsError
      ? `failed (${errorSummary(currentAbiWithdrawalsError)})`
      : "was not attempted";
    throw new Error(
      `Unable to read outstanding withdrawals for ARM ${armAddress}: ` +
        `reservedWithdrawLiquidity() ${reservedResult}; ` +
        `current ABI withdrawsQueued()/withdrawsClaimed() ${currentAbiResult}; ` +
        `legacy ABI withdrawsQueued()/withdrawsClaimed() failed (${errorSummary(err)})`,
      { cause: err },
    );
  }
};

const setArmBuffer = async (arm, signer, buffer, overrides = {}) => {
  try {
    return await arm.connect(signer).setARMBuffer(buffer, overrides);
  } catch (err) {
    if (!isMissingSelectorError(err)) throw err;
    const legacyArm = await legacyArmContract(arm, signer);
    try {
      return await legacyArm.setARMBuffer(buffer, overrides);
    } catch {
      throw new Error("ARM does not expose setARMBuffer(uint256)");
    }
  }
};

const estimateSetArmBufferGas = async (arm, signer, buffer) => {
  try {
    return await arm.connect(signer).setARMBuffer.estimateGas(buffer);
  } catch (err) {
    if (!isMissingSelectorError(err)) throw err;
    const legacyArm = await legacyArmContract(arm, signer);
    try {
      return await legacyArm.setARMBuffer.estimateGas(buffer);
    } catch {
      throw new Error("ARM does not expose setARMBuffer(uint256)");
    }
  }
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
      "function MAX_UNSTAKERS() view returns (uint8)",
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
  callAllocate,
  defaultBaseSymbol,
  estimateAllocateGas,
  estimateSetArmBufferGas,
  getArmBuffer,
  getOutstandingWithdrawals,
  legacyArmContract,
  liquiditySymbol,
  normalizeBaseSymbol,
  parseSwapCap,
  requestBaseAssetWithdrawal,
  resolveArmBase,
  resolveAssetAddress,
  setArmBuffer,
  setArmPrices,
  staticCallAllocate,
  claimBaseAssetWithdrawal,
  toConfigObject,
};
