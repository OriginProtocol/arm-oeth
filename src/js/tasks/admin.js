const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:admin");

async function allocate({ arm, signer }) {
  log(`About to allocate to/from the active lending market`);
  const tx = await arm.connect(signer).collectFees();
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
