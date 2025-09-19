const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { autoRequestWithdraw } = require("../tasks/liquidity");
const { sonic } = require("../utils/addresses");
const erc20Abi = require("../../abis/ERC20.json");
const armAbi = require("../../abis/OriginARM.json");

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
    `DEBUG env var in handler before being set: "${process.env.DEBUG}"`
  );

  // References to contracts
  const asset = new ethers.Contract(sonic.OSonicProxy, erc20Abi, signer);
  const arm = new ethers.Contract(sonic.OriginARM, armAbi, signer);

  await autoRequestWithdraw({
    signer,
    asset,
    arm,
    minAmount: 5000,
    confirm: true,
  });
};

module.exports = { handler };
