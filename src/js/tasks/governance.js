const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:governance");

async function setOperator({ contract, operator, signer }) {
  log(`About to set the Operator to ${operator}`);
  const tx = await contract.connect(signer).setOperator(operator);
  await logTxDetails(tx, "setOperator");
}

module.exports = { setOperator };
