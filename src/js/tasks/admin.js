const { formatUnits, parseUnits } = require("ethers");
const { ethers } = require("ethers");
const erc20Abi = require("../../abis/ERC20.json");

const { logTxDetails } = require("../utils/txLogger");
const {
  callAllocate,
  estimateAllocateGas,
  estimateSetArmBufferGas,
  getOutstandingWithdrawals,
  setArmBuffer,
  staticCallAllocate,
} = require("../utils/arm");

const log = require("../utils/logger")("task:admin");

async function limitGasPrice(signer, maxGasPriceGwei) {
  const { gasPrice } = await signer.provider.getFeeData();
  const maxGasPrice = parseUnits(maxGasPriceGwei.toString(), "gwei");

  if (gasPrice > maxGasPrice) {
    log(
      `Gas price ${formatUnits(gasPrice, "gwei")} gwei exceeds max of ${formatUnits(
        maxGasPrice,
        "gwei",
      )} gwei`,
    );
    return true;
  }

  log(`Current gas price: ${formatUnits(gasPrice, "gwei")} gwei`);
  return false;
}

async function allocate({
  arm,
  signer,
  threshold,
  execute = true,
  maxGasPrice: maxGasPriceGwei = 10,
  // Decimals of the ARM's liquidity asset. eg 18 for WETH, 6 for USDC.
  decimals = 18,
  // Omitted (undefined) means auto-detect the ARM contract version.
  armContractVersion = /** @type {string | undefined} */ (undefined),
}) {
  const activeMarketAddress = await arm.activeMarket();
  if (activeMarketAddress === ethers.ZeroAddress) {
    log(`No active lending market, skipping allocation`);
    return;
  }

  if (await limitGasPrice(signer, maxGasPriceGwei)) {
    log("Skipping allocation due to high gas price");
    return;
  }

  let liquidityDelta;
  if (armContractVersion === "v1") {
    liquidityDelta = await arm.allocate.staticCall();
  } else if (armContractVersion === "v2") {
    [, liquidityDelta] = await arm.allocate.staticCall();
  } else {
    liquidityDelta = await staticCallAllocate(arm);
  }

  const thresholdBN = parseUnits((threshold || "10").toString(), decimals);
  const withinThreshold =
    liquidityDelta < thresholdBN && liquidityDelta > -thresholdBN;

  // If the delta is positive and within threshold, skip
  if (withinThreshold && liquidityDelta >= 0n) {
    log(
      `Only ${formatUnits(liquidityDelta, decimals)} liquidity delta, skipping allocation as threshold is ${formatUnits(thresholdBN, decimals)}`,
    );
    return;
  }

  // If the delta is negative, check if there is a small amount left in the market and drain it if so
  if (liquidityDelta < 0n) {
    // Get the amount of liquidity available in the active market
    const activeMarket = new ethers.Contract(
      activeMarketAddress,
      ["function maxWithdraw(address) external view returns (uint256)"],
      signer,
    );
    const availableAssets = await activeMarket.maxWithdraw(
      await arm.getAddress(),
    );

    // If liquidity delta is within threshold but there are still more than threshold assets available in the market, skip
    if (withinThreshold && availableAssets > thresholdBN) {
      log(
        `Only ${formatUnits(liquidityDelta, decimals)} liquidity delta and ${formatUnits(availableAssets, decimals)} available assets > ${formatUnits(thresholdBN, decimals)} threshold, skipping allocation`,
      );
      return;
    }

    // Skip if transferring a small amount as its not gas efficient
    if (availableAssets < parseUnits("0.1", decimals)) {
      log(
        `Only ${formatUnits(availableAssets, decimals)} liquidity available in the active lending market, skipping allocation`,
      );
      return;
    }

    // Either the delta is above threshold or there is a small amount left in the market
    log(
      `Only ${formatUnits(availableAssets, decimals)} available in the active lending market, proceeding with allocation to drain remaining liquidity`,
    );
  }

  log(
    `About to allocate ${formatUnits(
      liquidityDelta,
      decimals,
    )} to/from the active lending market`,
  );

  if (execute) {
    // Add 10% buffer to gas limit
    let gasLimit = await estimateAllocateGas(arm, signer);
    gasLimit = (gasLimit * 11n) / 10n;

    const tx = await callAllocate(arm, signer, { gasLimit });
    await logTxDetails(tx, "allocate");
  }
}

async function collectFees({ arm, signer, decimals = 18 }) {
  // Get the amount of fees to be collected
  const fees = await arm.feesAccrued();
  const outstanding = await getOutstandingWithdrawals(arm);

  // Check there is enough liquidity to collect fees
  const liquidityAssetAddress = await arm.liquidityAsset();
  const liquidityAsset = new ethers.Contract(
    liquidityAssetAddress,
    erc20Abi,
    signer,
  );
  const liquidityBalance = await liquidityAsset.balanceOf(
    await arm.getAddress(),
  );
  const liquidityAvailable = liquidityBalance - outstanding;
  log(
    `Liquidity available in ARM: ${formatUnits(liquidityAvailable, decimals)}`,
  );

  if (fees > liquidityAvailable) {
    console.log(
      `Not enough liquidity to collect ${formatUnits(fees, decimals)} in fees. The ARM only has ${formatUnits(liquidityAvailable, decimals)} available.`,
    );
    return;
  }

  // Add 10% buffer to gas limit
  let gasLimit = await arm.connect(signer).collectFees.estimateGas();
  gasLimit = (gasLimit * 11n) / 10n;

  log(`About to collect ${formatUnits(fees, decimals)} ARM fees`);
  const tx = await arm.connect(signer).collectFees({ gasLimit });
  await logTxDetails(tx, "collectFees");
}

async function pauseARM({ arm, signer }) {
  // Skip if the ARM is already paused
  if (await arm.paused()) {
    log("ARM is already paused");
    return;
  }

  // Add 10% buffer to gas limit
  let gasLimit = await arm.connect(signer).pause.estimateGas();
  gasLimit = (gasLimit * 11n) / 10n;

  log("About to pause the ARM");
  const tx = await arm.connect(signer).pause({ gasLimit });
  await logTxDetails(tx, "pause");
}

async function setARMBuffer({ arm, signer, buffer, execute = true }) {
  if (buffer > 1) {
    throw new Error("Buffer value cannot be greater than 1");
  }
  const bufferBN = parseUnits((buffer || "0").toString(), 18);

  if (!execute) {
    log(`Would set ARM buffer to ${formatUnits(bufferBN)}`);
    return;
  }

  // Add 10% buffer to gas limit
  let gasLimit = await estimateSetArmBufferGas(arm, signer, bufferBN);
  gasLimit = (gasLimit * 11n) / 10n;

  log(`About to set ARM buffer to ${formatUnits(bufferBN)}`);
  const tx = await setArmBuffer(arm, signer, bufferBN, { gasLimit });
  await logTxDetails(tx, "setARMBuffer");
}

const CAP_MANAGER_ABI = [
  "function setLiquidityProviderCaps(address[] liquidityProviders, uint256 cap)",
  "function setTotalAssetsCap(uint248 totalAssetsCap)",
];

// Resolve the CapManager contract of an ARM.
async function resolveCapManager(arm, signer) {
  const capManagerAddress = await arm.capManager();
  if (capManagerAddress === ethers.ZeroAddress) {
    throw new Error("No CapManager configured for the ARM");
  }
  return new ethers.Contract(capManagerAddress, CAP_MANAGER_ABI, signer);
}

async function setTotalAssetsCap({
  arm,
  armName = "ARM",
  cap,
  signer,
  // Decimals of the ARM's liquidity asset. eg 18 for WETH, 6 for USDC.
  decimals = 18,
}) {
  const capBn = parseUnits(cap.toString(), decimals);

  const capManager = await resolveCapManager(arm, signer);

  log(`About to set total asset cap of ${cap} for the ${armName} ARM`);
  const tx = await capManager.setTotalAssetsCap(capBn);
  await logTxDetails(tx, "setTotalAssetsCap");
}

async function setLiquidityProviderCaps({
  accounts,
  arm,
  armName = "ARM",
  cap,
  signer,
  // Decimals of the ARM's liquidity asset. eg 18 for WETH, 6 for USDC.
  decimals = 18,
}) {
  const capBn = parseUnits(cap.toString(), decimals);

  const liquidityProviders = Array.isArray(accounts)
    ? accounts
    : accounts.split(",");

  const capManager = await resolveCapManager(arm, signer);

  log(
    `About to set deposit cap of ${cap} for liquidity providers ${liquidityProviders} for the ${armName} ARM`,
  );
  const tx = await capManager.setLiquidityProviderCaps(
    liquidityProviders,
    capBn,
  );
  await logTxDetails(tx, "setLiquidityProviderCaps");
}
module.exports = {
  allocate,
  collectFees,
  pauseARM,
  setARMBuffer,
  setLiquidityProviderCaps,
  setTotalAssetsCap,
};
