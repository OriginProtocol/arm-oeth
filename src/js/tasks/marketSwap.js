const { readFileSync } = require("fs");
const { parseUnits, Interface, Contract } = require("ethers");

const curvePoolAbi = require("../../abis/CurveStEthPool.json");

const { resolveAddress, resolveAsset } = require("../utils/assets");
const { resolveArmContract } = require("../utils/addressParser");
const { getSigner } = require("../utils/signers");
const { logTxDetails } = require("../utils/txLogger");
const {
  getArmPairConfig,
  getVenueConfig,
  getRequiredEnv,
} = require("../utils/marketSwapConfig");

const log = require("../utils/logger")("task:marketSwap");

const SWAP_TARGET_IFACES = {
  kyber: new Interface([
    "function swap(address tokenIn,address tokenOut,bytes data) returns (uint256 amountIn)",
  ]),
  "1inch": new Interface([
    "function swap(address tokenIn,address tokenOut,bytes data) returns (uint256 amountIn)",
  ]),
  curve: new Interface([
    "function swap(address tokenIn,address tokenOut,int128 i,int128 j,uint256 minDy) returns (uint256 amountIn)",
  ]),
  balancer: new Interface([
    "function swap(address tokenIn,address tokenOut,bytes32 poolId,uint256 minAmountIn,bytes userData) returns (uint256 amountIn)",
  ]),
};

const requireExactlyOne = (a, b, aName, bName) => {
  if ((!a && !b) || (a && b)) {
    throw new Error(`Must specify exactly one of --${aName} or --${bName}`);
  }
};

const isPresent = (value) => value !== undefined && value !== null;

const normalizeSymbol = (arm, symbol) => {
  const pair = getArmPairConfig(arm);
  if (symbol.toUpperCase() === pair.liquidity.toUpperCase())
    return pair.liquidity;
  if (symbol.toUpperCase() === pair.base.toUpperCase()) return pair.base;
  throw new Error(
    `Unsupported asset "${symbol}" for ARM "${arm}". Use ${pair.liquidity} or ${pair.base}`,
  );
};

const resolveTokenDirection = ({ arm, from, to }) => {
  const pair = getArmPairConfig(arm);

  requireExactlyOne(from, to, "from", "to");

  if (from) {
    const tokenOutSymbol = normalizeSymbol(arm, from);
    const tokenInSymbol =
      tokenOutSymbol === pair.liquidity ? pair.base : pair.liquidity;
    return { tokenInSymbol, tokenOutSymbol };
  }

  const tokenInSymbol = normalizeSymbol(arm, to);
  const tokenOutSymbol =
    tokenInSymbol === pair.liquidity ? pair.base : pair.liquidity;
  return { tokenInSymbol, tokenOutSymbol };
};

const readRouteFile = (routeFile) => {
  if (!routeFile) {
    throw new Error(`Route file is required for this venue`);
  }

  try {
    return JSON.parse(readFileSync(routeFile, "utf8"));
  } catch (err) {
    throw new Error(`Failed to read route file "${routeFile}"`, { cause: err });
  }
};

const getRouteAmountOut = (route) => {
  const amountOut =
    route.requestedAmountOut ??
    route.srcAmount ??
    route.amountOut ??
    route.amountIn ??
    route.quote?.srcAmount ??
    route.quote?.amountOut ??
    route.routeSummary?.amountIn ??
    route.tx?.amount;

  if (!isPresent(amountOut)) {
    return null;
  }

  return BigInt(amountOut.toString());
};

const getQuotedAmountIn = (route) => {
  const quoted =
    route.quotedAmountIn ??
    route.dstAmount ??
    route.returnAmount ??
    route.amountInQuoted ??
    route.quote?.quotedAmountIn ??
    route.quote?.amountIn ??
    route.quote?.dstAmount ??
    route.routeSummary?.amountOut ??
    route.amountIn;

  if (!isPresent(quoted)) {
    throw new Error(`Route file is missing a quoted amountIn field`);
  }

  return BigInt(quoted.toString());
};

const deriveVenueMinAmountIn = (quotedAmountIn, slippageBps) => {
  if (slippageBps < 0 || slippageBps > 10_000) {
    throw new Error(`Slippage must be between 0 and 10000 bps`);
  }

  return (quotedAmountIn * BigInt(10_000 - slippageBps)) / 10_000n;
};

const buildAggregatorTargetData = ({
  venue,
  tokenInAddress,
  tokenOutAddress,
  routeFile,
  amountOut,
  slippageBps,
}) => {
  const route = readRouteFile(routeFile);
  const routerCalldata =
    route.routerCalldata ?? route.data ?? route.tx?.data ?? route.routerData;

  if (!routerCalldata) {
    throw new Error(`Route file is missing router calldata`);
  }

  const routeAmountOut = getRouteAmountOut(route);
  if (routeAmountOut !== null && routeAmountOut !== amountOut) {
    throw new Error(
      `Route file amountOut ${routeAmountOut} does not match task amountOut ${amountOut}`,
    );
  }

  const quotedAmountIn = getQuotedAmountIn(route);
  const minAmountIn = deriveVenueMinAmountIn(quotedAmountIn, slippageBps);

  return {
    route,
    quotedAmountIn,
    minAmountIn,
    targetData: SWAP_TARGET_IFACES[venue].encodeFunctionData("swap", [
      tokenInAddress,
      tokenOutAddress,
      routerCalldata,
    ]),
  };
};

const buildCurveTargetData = async ({
  signer,
  tokenInAddress,
  tokenOutAddress,
  tokenInSymbol,
  tokenOutSymbol,
  amountOut,
  venueConfig,
  slippageBps,
}) => {
  const poolAddress =
    venueConfig.poolAddress ?? getRequiredEnv(venueConfig.poolAddressEnvVar);
  const curvePool = new Contract(poolAddress, curvePoolAbi, signer);

  const i = venueConfig.indices[tokenOutSymbol];
  const j = venueConfig.indices[tokenInSymbol];
  if (i === undefined || j === undefined) {
    throw new Error(`Curve venue config is missing token indexes`);
  }

  const quotedAmountIn = await curvePool["get_dy(int128,int128,uint256)"](
    i,
    j,
    amountOut,
  );
  const minAmountIn = deriveVenueMinAmountIn(
    BigInt(quotedAmountIn),
    slippageBps,
  );

  return {
    quotedAmountIn: BigInt(quotedAmountIn),
    minAmountIn,
    targetData: SWAP_TARGET_IFACES.curve.encodeFunctionData("swap", [
      tokenInAddress,
      tokenOutAddress,
      i,
      j,
      minAmountIn,
    ]),
  };
};

const buildBalancerTargetData = ({
  tokenInAddress,
  tokenOutAddress,
  venueConfig,
  routeFile,
  slippageBps,
}) => {
  const route = readRouteFile(routeFile);
  const quotedAmountIn = getQuotedAmountIn(route);
  const minAmountIn = deriveVenueMinAmountIn(quotedAmountIn, slippageBps);
  const poolId = route.poolId ?? getRequiredEnv(venueConfig.poolIdEnvVar);
  const userData = route.userData ?? "0x";

  return {
    route,
    quotedAmountIn,
    minAmountIn,
    targetData: SWAP_TARGET_IFACES.balancer.encodeFunctionData("swap", [
      tokenInAddress,
      tokenOutAddress,
      poolId,
      minAmountIn,
      userData,
    ]),
  };
};

const marketSwap = async ({
  arm,
  venue,
  amountOut,
  from,
  to,
  routeFile,
  slippageBps = 50,
}) => {
  const signer = await getSigner();
  const signerAddress = await signer.getAddress();
  const armContract = await resolveArmContract(arm);
  const network = await ethers.provider.getNetwork();
  const venueConfig = getVenueConfig({
    chainId: network.chainId,
    arm,
    venue,
  });

  const { tokenInSymbol, tokenOutSymbol } = resolveTokenDirection({
    arm,
    from,
    to,
  });

  const tokenInAsset = await resolveAsset(tokenInSymbol);
  const tokenInAddress = await tokenInAsset.getAddress();
  const tokenOutAsset = await resolveAsset(tokenOutSymbol);
  const tokenOutAddress = await tokenOutAsset.getAddress();
  const tokenOutDecimals = await tokenOutAsset.decimals();
  const parsedAmountOut = parseUnits(amountOut.toString(), tokenOutDecimals);
  const targetAddress = getRequiredEnv(venueConfig.targetEnvVar);

  let buildResult;
  if (venue === "kyber" || venue === "1inch") {
    buildResult = buildAggregatorTargetData({
      venue,
      tokenInAddress,
      tokenOutAddress,
      routeFile,
      amountOut: parsedAmountOut,
      slippageBps,
    });
  } else if (venue === "curve") {
    buildResult = await buildCurveTargetData({
      signer,
      tokenInAddress,
      tokenOutAddress,
      tokenInSymbol,
      tokenOutSymbol,
      amountOut: parsedAmountOut,
      venueConfig,
      slippageBps,
    });
  } else if (venue === "balancer") {
    buildResult = buildBalancerTargetData({
      tokenInAddress,
      tokenOutAddress,
      venueConfig,
      routeFile,
      slippageBps,
    });
  } else {
    throw new Error(
      `Unsupported venue "${venue}". Use kyber, 1inch, curve or balancer`,
    );
  }

  log(
    `About to market swap ${amountOut} ${tokenOutSymbol} out of ${arm} for ${tokenInSymbol} into ${arm} using ${venue} target ${targetAddress} from signer ${signerAddress}`,
  );
  log(
    `Quoted amountIn ${buildResult.quotedAmountIn.toString()} and min venue amountIn ${buildResult.minAmountIn.toString()} with ${slippageBps} bps slippage`,
  );

  const [
    allowedMarketSwapDeviation,
    withdrawsQueued,
    withdrawsClaimed,
    tokenOutBalance,
    tokenInBalance,
  ] = await Promise.all([
    armContract.allowedMarketSwapDeviation(),
    armContract.withdrawsQueued(),
    armContract.withdrawsClaimed(),
    tokenOutAsset.balanceOf(await armContract.getAddress()),
    tokenInAsset.balanceOf(await armContract.getAddress()),
  ]);

  const outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;
  const availableTokenOut =
    tokenOutAddress.toLowerCase() ===
    (await armContract.liquidityAsset()).toLowerCase()
      ? tokenOutBalance - outstandingWithdrawals
      : tokenOutBalance;

  log(
    `ARM tokenOut balance ${tokenOutBalance.toString()}, tokenIn balance ${tokenInBalance.toString()}, outstanding withdrawals ${outstandingWithdrawals.toString()}, available tokenOut ${availableTokenOut.toString()}, allowed deviation ${allowedMarketSwapDeviation.toString()}`,
  );

  const marketSwapFn = armContract
    .connect(signer)
    ["marketSwap(address,address,uint256,address,bytes)"];

  const tx = await marketSwapFn(
    tokenInAddress,
    tokenOutAddress,
    parsedAmountOut,
    targetAddress,
    buildResult.targetData,
    { gasLimit: 5_000_000 },
  );

  await logTxDetails(tx, "market swap");
};

module.exports = {
  marketSwap,
  buildAggregatorTargetData,
  deriveVenueMinAmountIn,
  getQuotedAmountIn,
  getRouteAmountOut,
  resolveTokenDirection,
  readRouteFile,
};
