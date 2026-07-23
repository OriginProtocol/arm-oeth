const { Contract, parseUnits, MaxInt256 } = require("ethers");

const { resolveAddress } = require("../utils/assets");
const {
  defaultBaseSymbol,
  liquiditySymbol,
  normalizeBaseSymbol,
} = require("../utils/arm");
const { getSigner } = require("../utils/signers");
const { logTxDetails } = require("../utils/txLogger");
const { resolveArmContract } = require("../utils/addressParser");

const log = require("../utils/logger")("task:swap");

const tokenDecimals = async (tokenAddress, signer) =>
  Number(
    await new Contract(
      tokenAddress,
      ["function decimals() view returns (uint8)"],
      signer,
    ).decimals(),
  );

const swap = async ({ arm, from, to, amount, base }) => {
  if (from && to) {
    throw new Error(
      `Cannot specify both from and to asset. It has to be one or the other`,
    );
  }
  const signer = await getSigner();
  const signerAddress = await signer.getAddress();

  const armContract = await resolveArmContract(arm);

  if (from) {
    const fromAddress = await resolveAddress(from);

    const to = otherSymbol(arm, from, base);
    const toAddress = await resolveAddress(to);

    const fromDecimals = await tokenDecimals(fromAddress, signer);
    const fromAmount = parseUnits(amount.toString(), fromDecimals);

    log(`About to swap ${amount} ${from} to ${to} for ${signerAddress}`);

    const tx = await armContract
      .connect(signer)
      [
        "swapExactTokensForTokens(address,address,uint256,uint256,address)"
      ](fromAddress, toAddress, fromAmount, 0, signerAddress);

    await logTxDetails(tx, "swap exact from");
  } else if (to) {
    const from = otherSymbol(arm, to, base);
    const fromAddress = await resolveAddress(from);

    const toAddress = await resolveAddress(to);

    const toDecimals = await tokenDecimals(toAddress, signer);
    const toAmount = parseUnits(amount.toString(), toDecimals);

    log(`About to swap ${from} to ${amount} ${to} for ${signerAddress}`);

    const tx = await armContract
      .connect(signer)
      [
        "swapTokensForExactTokens(address,address,uint256,uint256,address)"
      ](fromAddress, toAddress, toAmount, MaxInt256, signerAddress);

    await logTxDetails(tx, "swap exact to");
  } else {
    throw new Error(`Must specify either from or to asset`);
  }
};

const otherSymbol = (arm, symbol, base) => {
  const normalizedSymbol = symbol.toString().replace(/-/g, "").toUpperCase();
  const baseSymbol = normalizeBaseSymbol(base) ?? defaultBaseSymbol(arm);
  const liquidSymbol = liquiditySymbol(arm);

  if (normalizedSymbol === liquidSymbol.toUpperCase()) return baseSymbol;
  return liquidSymbol;
};

module.exports = { swap };
