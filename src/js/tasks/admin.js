const { formatUnits, parseUnits } = require("ethers");
const { ethers } = require("ethers");
const erc20Abi = require("../../abis/ERC20.json");

const { logTxDetails } = require("../utils/txLogger");

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
  // V1 on sonic everywhere else V2
  armContractVersion = "v2",
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
    // The old implementation returns only liquidityDelta
    liquidityDelta = await arm.allocate.staticCall();
  } else if (armContractVersion === "v2") {
    // 1. Call the allocate static call to get the return values
    // Returned value is a tuple of two int256 values
    [, liquidityDelta] = await arm.allocate.staticCall();
  } else {
    throw new Error("Invalid ARM contract version");
  }

  const thresholdBN = parseUnits((threshold || "10").toString(), 18);
  const withinThreshold =
    liquidityDelta < thresholdBN && liquidityDelta > -thresholdBN;

  // If the delta is positive and within threshold, skip
  if (withinThreshold && liquidityDelta >= 0n) {
    log(
      `Only ${formatUnits(liquidityDelta)} liquidity delta, skipping allocation as threshold is ${formatUnits(thresholdBN)}`,
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
        `Only ${formatUnits(liquidityDelta)} liquidity delta and ${formatUnits(availableAssets)} available assets > ${formatUnits(thresholdBN)} threshold, skipping allocation`,
      );
      return;
    }

    // Skip if transferring a small amount as its not gas efficient
    if (availableAssets < parseUnits("0.1", 18)) {
      log(
        `Only ${formatUnits(availableAssets)} liquidity available in the active lending market, skipping allocation`,
      );
      return;
    }

    // Either the delta is above threshold or there is a small amount left in the market
  }

  log(
    `About to allocate ${formatUnits(
      liquidityDelta,
    )} to/from the active lending market`,
  );

  if (execute) {
    // Add 10% buffer to gas limit
    let gasLimit = await arm.connect(signer).allocate.estimateGas();
    gasLimit = (gasLimit * 11n) / 10n;

    const tx = await arm.connect(signer).allocate({ gasLimit });
    await logTxDetails(tx, "allocate");
  }
}

async function collectFees({ arm, signer }) {
  // Get the amount of fees to be collected
  const fees = await arm.feesAccrued();
  const queued = await arm.withdrawsQueued();
  const claimed = await arm.withdrawsClaimed();

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
  const liquidityAvailable = liquidityBalance + claimed - queued;
  log(`Liquidity available in ARM: ${formatUnits(liquidityAvailable)}`);

  if (fees > liquidityAvailable) {
    console.log(
      `Not enough liquidity to collect ${formatUnits(fees)} in fees. The ARM only has ${formatUnits(liquidityAvailable)} available.`,
    );
    return;
  }

  // Add 10% buffer to gas limit
  let gasLimit = await arm.connect(signer).collectFees.estimateGas();
  gasLimit = (gasLimit * 11n) / 10n;

  log(`About to collect ${formatUnits(fees)} ARM fees`);
  const tx = await arm.connect(signer).collectFees({ gasLimit });
  await logTxDetails(tx, "collectFees");
}

async function setARMBuffer({ arm, signer, buffer }) {
  if (buffer > 1) {
    throw new Error("Buffer value cannot be greater than 1");
  }
  const bufferBN = parseUnits((buffer || "0").toString(), 18);

  // Add 10% buffer to gas limit
  let gasLimit = await arm.connect(signer).setARMBuffer.estimateGas(bufferBN);
  gasLimit = (gasLimit * 11n) / 10n;

  log(`About to set ARM buffer to ${formatUnits(bufferBN)}`);
  const tx = await arm.connect(signer).setARMBuffer(bufferBN, { gasLimit });
  await logTxDetails(tx, "setARMBuffer");
}

module.exports = {
  allocate,
  collectFees,
  setARMBuffer,
};
