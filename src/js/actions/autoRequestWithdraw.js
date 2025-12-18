const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { autoRequestWithdraw } = require("../tasks/liquidityAutomation");
const { mainnet } = require("../utils/addresses");
const erc20Abi = require("../../abis/ERC20.json");
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
  const baseAsset = new ethers.Contract(mainnet.OETHProxy, erc20Abi, signer);
  const arm = new ethers.Contract(mainnet.OethARM, oethARMAbi, signer);

  await autoRequestWithdraw({
    signer,
    baseAsset,
    arm,
    minAmount: 5,
    confirm: true,
  });
};

module.exports = { handler };
