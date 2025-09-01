const { Defender } = require("@openzeppelin/defender-sdk");
const { ethers } = require("ethers");

const { autoClaimWithdraw } = require("../tasks/liquidityAutomation");
const { sonic } = require("../utils/addresses");
const { logTxDetails } = require("../utils/txLogger");
const erc20Abi = require("../../abis/ERC20.json");
const armAbi = require("../../abis/OriginARM.json");
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
  const liquidityAsset = new ethers.Contract(sonic.WS, erc20Abi, signer);
  const vault = new ethers.Contract(sonic.OSonicVaultProxy, vaultAbi, signer);
  const arm = new ethers.Contract(sonic.OriginARM, armAbi, signer);

  const requestIds = await autoClaimWithdraw({
    signer,
    liquidityAsset,
    arm,
    vault,
    confirm: true,
  });

  console.log(`Claimed requests "${requestIds}"`);

  // If any requests were claimed
  if (requestIds?.length > 0) {
    // Add 10% buffer to gas limit
    let gasLimit = await arm.connect(signer).allocate.estimateGas();
    gasLimit = (gasLimit * 12n) / 10n;
    
    // Allocate any excess liquidity to the lending market
    const tx = await arm.allocate({ gasLimit });
    await logTxDetails(tx, "allocate");
  }
};

module.exports = { handler };
