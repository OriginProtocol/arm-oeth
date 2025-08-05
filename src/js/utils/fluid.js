const { parseUnits } = require("ethers");
const { ethers } = require("ethers");

const quoterAbi = require("../../abis/FluidDexResolver.json");
const wstEthAbi = require("../../abis/wstETH.json");
const addresses = require("./addresses");
const { getSigner } = require("./signers");

const log = require("../utils/logger")("utils:uniswap");

const getFluidSpotPrices = async ({ amount, blockTag, gas }) => {
  const signer = await getSigner();
  const quoter = new ethers.Contract(
    addresses.mainnet.FluidDexResolver,
    quoterAbi,
    signer
  );

  const wstEth = new ethers.Contract(
    addresses.mainnet.wstETH,
    wstEthAbi,
    signer
  );

  const amountBI = parseUnits(amount.toString(), 18);

  // --- Swap WETH for stETH ---
  const wstEthAmount = await quoter
    .connect(signer)
    .estimateSwapIn.staticCall(
      addresses.mainnet.FluidWstEthEthPool,
      false,
      amountBI,
      0,
      { blockTag }
    );

  const buyToAmount = await wstEth.getStETHByWstETH(wstEthAmount);
  log(`buyToAmount: ${buyToAmount}`);
  // stETH/ETH rate = ETH amount / stETH amount
  const buyPrice = (amountBI * BigInt(1e18)) / buyToAmount;

  // --- Swap stETH for WETH ---
  // Convert stETH to wstETH
  const wstETHAmount = await wstEth.getWstETHByStETH(amountBI);
  log(`wstETHAmount: ${wstETHAmount} ${typeof wstETHAmount}`);
  // Convert wstETH to WETH
  const sellToAmount = await quoter
    .connect(signer)
    .estimateSwapIn.staticCall(
      addresses.mainnet.FluidWstEthEthPool,
      true,
      wstETHAmount,
      0,
      { blockTag }
    );

  // stETH/WETH rate = WETH amount / stETH amount
  const sellPrice = (sellToAmount * BigInt(1e18)) / amountBI;

  const midPrice = (buyPrice + sellPrice) / 2n;
  const spread = buyPrice - sellPrice;

  if (!gas) {
    return {
      buyToAmount,
      buyPrice,
      sellToAmount,
      sellPrice,
      midPrice,
      spread,
    };
  }

  const buyGas = await quoter
    .connect(signer)
    .estimateSwapIn.estimateGas(
      addresses.mainnet.FluidWstEthEthPool,
      false,
      amountBI,
      0,
      { blockTag }
    );
  const sellGas = await quoter
    .connect(signer)
    .estimateSwapIn.estimateGas(
      addresses.mainnet.FluidWstEthEthPool,
      true,
      amountBI,
      0,
      { blockTag }
    );

  return {
    buyToAmount,
    buyPrice,
    buyGas,
    sellToAmount,
    sellPrice,
    sellGas,
    midPrice,
    spread,
  };
};

module.exports = { getFluidSpotPrices };
