const { parseUnits } = require("ethers");

const curvePoolAbi = require("../../abis/CurveStEthPool.json");

const getCurvePrices = async ({ amount, poolAddress, blockTag, gas }) => {
  const pool = await ethers.getContractAt(curvePoolAbi, poolAddress);

  const amountBI = parseUnits(amount.toString(), 18);

  // Swap ETH for stETH
  const buyToAmount = await pool["get_dy(int128,int128,uint256)"](
    0,
    1,
    amountBI,
    { blockTag }
  );
  // stETH/ETH rate = ETH amount / stETH amount
  const buyPrice = (amountBI * BigInt(1e18)) / buyToAmount;

  // Swap stETH for ETH
  const sellToAmount = await pool["get_dy(int128,int128,uint256)"](
    1,
    0,
    amountBI,
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

  const buyGas = await pool["get_dy(int128,int128,uint256)"].estimateGas(
    0,
    1,
    amountBI,
    { blockTag }
  );
  const sellGas = await pool["get_dy(int128,int128,uint256)"].estimateGas(
    1,
    0,
    amountBI,
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

module.exports = { getCurvePrices };
