const {
  DefenderRelaySigner,
  DefenderRelayProvider,
} = require("defender-relay-client/lib/ethers");
const { ethers } = require("ethers");

const { autoClaimWithdraw } = require("../tasks/liquidity");
const { mainnet } = require("../utils/addresses");
const erc20Abi = require("../../abis/ERC20.json");
const oethARMAbi = require("../../abis/OethARM.json");
const vaultAbi = require("../../abis/vault.json");

// Entrypoint for the Autotask
const handler = async (event) => {
  // Initialize defender relayer provider and signer
  const provider = new DefenderRelayProvider(event);
  const signer = new DefenderRelaySigner(event, provider, { speed: "fastest" });

  console.log(
    `DEBUG env var in handler before being set: "${process.env.DEBUG}"`
  );

  // References to contracts
  const weth = new ethers.Contract(mainnet.WETH, erc20Abi, signer);
  const vault = new ethers.Contract(mainnet.OETHVaultProxy, vaultAbi, signer);
  const oethARM = new ethers.Contract(mainnet.OethARM, oethARMAbi, signer);

  try {
    await autoClaimWithdraw({
      signer,
      weth,
      oethARM,
      vault,
      confirm: true,
    });
  } catch (error) {
    console.error(error);
  }
};

module.exports = { handler };
