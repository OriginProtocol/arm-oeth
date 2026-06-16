const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { requestEtherFiWithdrawals } = require("../tasks/etherfiQueue");
const { runForBases } = require("./priceActionUtils");
const { mainnet } = require("../utils/addresses");
const erc20Abi = require("../../abis/ERC20.json");
const etherFiARMAbi = require("../../abis/EtherFiARM.json");

// Entrypoint for the Defender Action
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
  const eeth = new ethers.Contract(mainnet.eETH, erc20Abi, signer);
  const arm = new ethers.Contract(mainnet.etherfiARM, etherFiARMAbi, signer);

  await runForBases({
    bases: ["EETH", "WEETH"],
    actionName: "Requesting withdrawals",
    fn: requestEtherFiWithdrawals,
    options: {
      signer,
      eeth,
      arm,
      armName: "EtherFi",
      minAmount: "0.1",
      thresholdAmount: 10,
    },
  });
};

module.exports = { handler };
