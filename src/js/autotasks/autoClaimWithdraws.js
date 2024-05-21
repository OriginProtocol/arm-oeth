const {
  DefenderRelaySigner,
  DefenderRelayProvider,
} = require("defender-relay-client/lib/ethers");
const { ethers } = require("ethers");

const { autoClaimStEth } = require("../tasks/liquidity");
const addresses = require("../utils/addresses");
const oethARMAbi = require("../../abis/OEthARM.json");
const LidoStEthWithdrawalQueue = require("../../abis/LidoWithdrawQueue.json");

// Entrypoint for the Autotask
const handler = async (event) => {
  // Initialize defender relayer provider and signer
  const provider = new DefenderRelayProvider(event);
  const signer = new DefenderRelaySigner(event, provider, { speed: "fastest" });

  console.log(
    `DEBUG env var in handler before being set: "${process.env.DEBUG}"`
  );

  // References to contracts
  const oSwap = new ethers.Contract(
    addresses.mainnet.OEthARM,
    oethARMAbi,
    signer
  );
  const withdrawalQueue = new ethers.Contract(
    addresses.mainnet.stETHWithdrawalQueue,
    LidoStEthWithdrawalQueue,
    signer
  );

  await autoClaimStEth({
    asset: "WETH",
    signer,
    oSwap,
    withdrawalQueue,
    confirm: false,
  });
};

module.exports = { handler };
