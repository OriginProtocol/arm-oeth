const {
  DefenderRelaySigner,
  DefenderRelayProvider,
} = require("defender-relay-client/lib/ethers");
const { ethers } = require("ethers");

const { autoWithdraw } = require("../tasks/liquidity");
const { mainnet } = require("../utils/addresses");
const erc20Abi = require("../../abis/ERC20.json");
const oethARMAbi = require("../../abis/OethARM.json");

// Entrypoint for the Autotask
const handler = async (event) => {
  // Initialize defender relayer provider and signer
  const provider = new DefenderRelayProvider(event);
  const signer = new DefenderRelaySigner(event, provider, { speed: "fastest" });

  console.log(
    `DEBUG env var in handler before being set: "${process.env.DEBUG}"`
  );

  // References to contracts
  const oeth = new ethers.Contract(mainnet.OETH, erc20Abi, signer);
  const oethARM = new ethers.Contract(mainnet.OethARM, oethARMAbi, signer);

  await autoWithdraw({
    signer,
    oethARM,
    oeth,
    minAmount: 2,
  });
};

module.exports = { handler };
