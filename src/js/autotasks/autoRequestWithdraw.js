const {
  DefenderRelaySigner,
  DefenderRelayProvider,
} = require("defender-relay-client/lib/ethers");
const { ethers } = require("ethers");

const { autoWithdrawStEth } = require("../tasks/liquidity");
const addresses = require("../utils/addresses");
const erc20Abi = require("../../abis/ERC20.json");
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
  const stEth = new ethers.Contract(addresses.mainnet.stETH, erc20Abi, signer);
  const weth = new ethers.Contract(addresses.mainnet.WETH, erc20Abi, signer);
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

  await autoWithdrawStEth({
    signer,
    stEth,
    weth,
    oSwap,
    withdrawalQueue,
    pair: "OETH/WETH",
    minAmount: 2,
    confirm: false,
    divisor: 20n, // Leave 1/20 of the liquidity as OETH
  });
};

module.exports = { handler };

