const { formatUnits, parseUnits } = require("ethers");

const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:admin");

async function allocate({ arm, signer, threshold }) {
  const liquidityDelta = await arm.allocate.staticCall();

  const thresholdBN = parseUnits((threshold || "10").toString(), 18);
  if (liquidityDelta < thresholdBN && liquidityDelta > -thresholdBN) {
    log(
      `Only ${formatUnits(
        liquidityDelta
      )} liquidity delta, skipping allocation as threshold is ${formatUnits(
        thresholdBN
      )}`
    );
    return;
  }

  // Add 10% buffer to gas limit
  let gasLimit = await arm.connect(signer).allocate.estimateGas();
  gasLimit = (gasLimit * 11n) / 10n;

  log(
    `About to allocate ${formatUnits(
      liquidityDelta
    )} to/from the active lending market`
  );
  const tx = await arm.connect(signer).allocate({ gasLimit });
  await logTxDetails(tx, "allocate");
}

async function collectFees({ arm, signer }) {
  log(`About to collect ARM fees`);
  const tx = await arm.connect(signer).collectFees();
  await logTxDetails(tx, "collectFees");
}

module.exports = {
  allocate,
  collectFees,
};
