const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { autoClaimWithdraw } = require("../tasks/liquidity");
const { mainnet } = require("../utils/addresses");
const erc20Abi = require("../../abis/ERC20.json");
const oethARMAbi = require("../../abis/OethARM.json");
const vaultAbi = require("../../abis/vault.json");

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
  const liquidityAsset = new ethers.Contract(mainnet.WETH, erc20Abi, signer);
  const vault = new ethers.Contract(mainnet.OETHVaultProxy, vaultAbi, signer);
  const arm = new ethers.Contract(mainnet.OethARM, oethARMAbi, signer);

  await autoClaimWithdraw({
    signer,
    liquidityAsset,
    arm,
    vault,
    confirm: true,
  });
};

module.exports = { handler };
