const { logTxDetails } = require("../utils/txLogger");
const { ethereumAddress } = require("../utils/regex");

const log = require("../utils/logger")("task:proxy");

async function upgradeProxy({ proxy, impl, signer }) {
  if (!proxy.match(ethereumAddress)) {
    throw new Error(`Invalid proxy address: ${proxy}`);
  }
  if (!impl.match(ethereumAddress)) {
    throw new Error(`Invalid implementation contract address: ${impl}`);
  }

  const proxyContract = await ethers.getContractAt("Proxy", proxy);

  log(`About to upgrade proxy ${proxy} to implementation ${impl}`);
  const tx = await proxyContract.connect(signer).upgradeTo(impl);
  await logTxDetails(tx, "proxy upgrade");
}

module.exports = {
  upgradeProxy,
};
