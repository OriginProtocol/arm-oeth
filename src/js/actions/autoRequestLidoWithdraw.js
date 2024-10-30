const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { requestLidoWithdrawals } = require("../tasks/lidoQueue");
const { mainnet } = require("../utils/addresses");
const erc20Abi = require("../../abis/ERC20.json");
const lidoARMAbi = require("../../abis/LidoARM.json");

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
    `DEBUG env var in handler before being set: "${process.env.DEBUG}"`
  );

  // References to contracts
  const steth = new ethers.Contract(mainnet.stETH, erc20Abi, signer);
  const arm = new ethers.Contract(mainnet.lidoARM, lidoARMAbi, signer);

  await requestLidoWithdrawals({
    signer,
    steth,
    arm,
    minAmount: 1,
  });
};

module.exports = { handler };
