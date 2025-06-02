const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:admin");

async function allocate({ arm, signer }) {
  log(`About to allocate to/from the active lending market`);
  // Fixing the gas limit as the tx was a lot of the txs were failing wth out of gas errors
  const tx = await arm.connect(signer).allocate({ gasLimit: 3000000n });
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
