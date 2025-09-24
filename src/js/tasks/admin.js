const { formatUnits, parseUnits } = require("ethers");
const { ethers } = require("ethers");
const erc20Abi = require("../../abis/ERC20.json");

const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:admin");

async function allocate({ arm, signer, threshold }) {
  const liquidityDelta = await arm.allocate.staticCall();

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

  // Add 10% buffer to gas limit
  let gasLimit = await arm.connect(signer).allocate.estimateGas();
  gasLimit = (gasLimit * 11n) / 10n;

  log(
    `About to allocate ${formatUnits(
      liquidityDelta,
    )} to/from the active lending market`,
  );
  const tx = await arm.connect(signer).allocate({ gasLimit });
  await logTxDetails(tx, "allocate");
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
  if (buffer >= 1) {
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
