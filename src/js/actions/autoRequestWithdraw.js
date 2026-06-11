const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { autoRequestWithdraw } = require("../tasks/liquidityAutomation");
const { runForBases } = require("./priceActionUtils");
const { mainnet } = require("../utils/addresses");
const oethARMAbi = require("../../abis/OethARM.json");

// Entrypoint for the Autotask
const handler = async (event) => {
  // Initialize defender relayer provider and signer
  const client = new Defender(event);
  const provider = client.relaySigner.getProvider({ ethersVersion: "v6" });
  const signer = await client.relaySigner.getSigner(provider, {
    speed: "fastest",
    ethersVersion: "v6",
  });

  console.log(
    `DEBUG env var in handler before being set: "${process.env.DEBUG}"`,
  );

  // References to contracts
  const arm = new ethers.Contract(mainnet.OethARM, oethARMAbi, signer);

  await runForBases({
    bases: ["OETH", "WOETH"],
    actionName: "Requesting withdrawals",
    fn: autoRequestWithdraw,
    options: {
      signer,
      arm,
      armName: "Oeth",
      minAmount: "0.1",
      thresholdAmount: 10,
    },
  });
};

module.exports = { handler };
