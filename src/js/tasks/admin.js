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
  targetLiquidityDelta,
  execute = true,
  maxGasPrice: maxGasPriceGwei = 10,
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

  if (targetLiquidityDelta === undefined || targetLiquidityDelta === null) {
    throw new Error("targetLiquidityDelta is required");
  }

  const targetLiquidityDeltaBN = parseUnits(targetLiquidityDelta.toString(), 18);

  log(
    `About to allocate ${formatUnits(
      targetLiquidityDeltaBN,
    )} to/from the active lending market`,
  );

  if (execute) {
    // Add 10% buffer to gas limit
    let gasLimit = await arm.connect(signer).allocate.estimateGas(targetLiquidityDeltaBN);
    gasLimit = (gasLimit * 11n) / 10n;

    const tx = await arm.connect(signer).allocate(targetLiquidityDeltaBN, { gasLimit });
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

module.exports = {
  allocate,
  collectFees,
};
