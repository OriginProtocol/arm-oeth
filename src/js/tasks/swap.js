const { parseUnits, MaxInt256 } = require("ethers");

const addresses = require("../utils/addresses");
const { resolveAddress } = require("../utils/assets");
const { getSigner } = require("../utils/signers");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:swap");

const swap = async (taskArguments, hre) => {
  const { from, to, amount } = taskArguments;
  if (from && to) {
    throw new Error(
      `Cannot specify both from and to asset. It has to be one or the other`
    );
  }
  const signer = await getSigner();
  const signerAddress = await signer.getAddress();

  const oethARM = await hre.ethers.getContractAt(
    "OEthARM",
    addresses.mainnet.OEthARM
  );

  if (from) {
    const fromAddress = resolveAddress(from);

    const to = from === "OETH" ? "WETH" : "OETH";
    const toAddress = resolveAddress(to);

    const fromAmount = parseUnits(amount.toString(), 18);

    log(`About to swap ${amount} ${from} to ${to} for ${signerAddress}`);

    const tx = await oethARM
      .connect(signer)
      .swapExactTokensForTokens(
        fromAddress,
        toAddress,
        fromAmount,
        0,
        signerAddress
      );

    await logTxDetails(tx, "swap exact from");
  } else if (to) {
    const from = to === "OETH" ? "WETH" : "OETH";
    const fromAddress = resolveAddress(from);

    const toAddress = resolveAddress(to);

    const toAmount = parseUnits(amount.toString(), 18);

    log(`About to swap ${from} to ${amount} ${to} for ${signerAddress}`);

    const tx = await oethARM
      .connect(signer)
      .swapTokensForExactTokens(
        fromAddress,
        toAddress,
        toAmount,
        MaxInt256,
        signerAddress
      );

    await logTxDetails(tx, "swap exact to");
  } else {
    throw new Error(`Must specify either from or to asset`);
  }
};

module.exports = { swap };
