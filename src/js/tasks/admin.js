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
}) {
  if (await limitGasPrice(signer, maxGasPriceGwei)) {
    log("Skipping allocation due to high gas price");
    return;
  }

  // 1. Call the allocate static call to get the return values
  // Returned value can be either a single int256 or a tuple of two int256 values
  let liquidityDelta;
  [, liquidityDelta] = await arm.allocate.staticCall();

  const thresholdBN = parseUnits((threshold || "10").toString(), 18);
  if (liquidityDelta < thresholdBN && liquidityDelta > -thresholdBN) {
    log(
      `Only ${formatUnits(
        liquidityDelta,
      )} liquidity delta, skipping allocation as threshold is ${formatUnits(
        thresholdBN,
      )}`,
    );
    return;
  }

  // if the liquidity delta is negative, check if there is any liquidity in the lending market
  if (liquidityDelta < 0) {
    // Get the active market wrapper contract
    const activeMarketAddress = await arm.activeMarket();
    if (activeMarketAddress !== ethers.ZeroAddress) {
      const activeMarket = new ethers.Contract(
        activeMarketAddress,
        ["function market() external view returns (address)"],
        signer,
      );

      // Get the underlying ERC-4626 vault. eg Silo or Morpho Vault
      const underlyingVaultAddress = await activeMarket.market();
      const underlyingVault = new ethers.Contract(
        underlyingVaultAddress,
        ["function maxWithdraw(address) external view returns (uint256)"],
        signer,
      );

      // Check there is liquidity available to withdraw from the lending market
      const availableAssets =
        await underlyingVault.maxWithdraw(activeMarketAddress);
      if (availableAssets < parseUnits("0.01", 18)) {
        log(
          `Only ${formatUnits(availableAssets)} liquidity available in the active lending market, skipping allocation`,
        );
        return;
      }
    }
  }

  // Add 10% buffer to gas limit
  let gasLimit = await arm.connect(signer).allocate.estimateGas();
  gasLimit = (gasLimit * 11n) / 10n;

  log(
    `About to allocate ${formatUnits(
      liquidityDelta,
    )} to/from the active lending market`,
  );
  if (execute) {
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
