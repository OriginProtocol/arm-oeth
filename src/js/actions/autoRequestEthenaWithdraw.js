const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { requestEthenaWithdrawals } = require("../tasks/ethenaQueue");
const { mainnet } = require("../utils/addresses");
const erc20Abi = require("../../abis/ERC20.json");
const ethenaARMAbi = require("../../abis/EthenaARM.json");

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
  const susde = new ethers.Contract(mainnet.sUSDe, erc20Abi, signer);
  const arm = new ethers.Contract(mainnet.ethenaARM, ethenaARMAbi, signer);

  await requestEthenaWithdrawals({
    signer,
    susde,
    arm,
    minAmount: "100",
    thresholdAmount: 1000,
  });
};

module.exports = { handler };
