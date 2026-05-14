const { formatUnits, parseUnits } = require("ethers");
const { baseWithdrawAmount } = require("./liquidityAutomation");

const { adapterContract, resolveArmBase } = require("../utils/arm");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:lidoQueue");

const requestLidoWithdrawals = async (options) => {
  const { amount, signer, arm } = options;
  const { baseSymbol, baseAddress } = await resolveArmBase(options);

  const withdrawAmount = amount
    ? parseUnits(amount.toString())
    : await baseWithdrawAmount(options);
  if (!withdrawAmount || withdrawAmount === 0n) return;

  log(
    `About to request ${formatUnits(withdrawAmount)} ${baseSymbol} withdrawal from Lido`,
  );

  const tx = await arm
    .connect(signer)
    .requestBaseAssetRedeem(baseAddress, withdrawAmount);

  await logTxDetails(tx, "requestRedeem");
};

const claimLidoWithdrawals = async (options) => {
  const { signer, arm, id } = options;
  const { baseAddress, config } = await resolveArmBase(options);
  const adapter = await adapterContract(config.adapter, signer);

  let shares;
  if (id) {
    shares = await adapter["requestShares(uint256)"](id);
  } else {
    try {
      [shares] = await adapter.claimableRedeem();
    } catch {
      shares = 0n;
    }
    if (shares === 0n) {
      log("No finalized Lido withdrawal requests to claim");
      return;
    }
  }

  log(`About to claim ${formatUnits(shares)} Lido adapter shares`);
  const tx = await arm
    .connect(signer)
    .claimBaseAssetRedeem(baseAddress, shares);
  await logTxDetails(tx, "claimRedeem");
};

module.exports = {
  requestLidoWithdrawals,
  claimLidoWithdrawals,
};
