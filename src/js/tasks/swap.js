const { parseUnits, MaxInt256 } = require("ethers");

const { resolveAddress } = require("../utils/assets");
const { getSigner } = require("../utils/signers");
const { logTxDetails } = require("../utils/txLogger");
const { parseAddress } = require("../utils/addressParser");

const log = require("../utils/logger")("task:swap");

const swap = async ({ arm, from, to, amount }) => {
  if (from && to) {
    throw new Error(
      `Cannot specify both from and to asset. It has to be one or the other`
    );
  }
  const signer = await getSigner();
  const signerAddress = await signer.getAddress();

  const armAddress = await parseAddress(`${arm.toUpperCase()}_ARM`);
  const armContract = await ethers.getContractAt(`${arm}ARM`, armAddress);

  if (from) {
    const fromAddress = await resolveAddress(from);

    const to = otherSymbol(arm, from);
    const toAddress = await resolveAddress(to);

    const fromAmount = parseUnits(amount.toString(), 18);

    log(`About to swap ${amount} ${from} to ${to} for ${signerAddress}`);

    const tx = await armContract
      .connect(signer)
      ["swapExactTokensForTokens(address,address,uint256,uint256,address)"](
        fromAddress,
        toAddress,
        fromAmount,
        0,
        signerAddress
      );

    await logTxDetails(tx, "swap exact from");
  } else if (to) {
    const from = otherSymbol(arm, to);
    const fromAddress = await resolveAddress(from);

    const toAddress = await resolveAddress(to);

    const toAmount = parseUnits(amount.toString(), 18);

    log(`About to swap ${from} to ${amount} ${to} for ${signerAddress}`);

    const tx = await armContract
      .connect(signer)
      ["swapTokensForExactTokens(address,address,uint256,uint256,address)"](
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

const otherSymbol = (arm, symbol) => {
  if (arm === "Oeth") {
    return symbol === "OETH" ? "WETH" : "OETH";
  } else if (arm === "Origin") {
    return symbol === "OS" ? "WS" : "OS";
  } else if (arm === "Lido") {
    return symbol === "stETH" ? "WETH" : "stETH";
  }
  throw new Error(`Unknown ARM ${arm}. Has to be Oeth, Lido or Origin`);
};

module.exports = { swap };
