const { formatUnits } = require("ethers");

const { parseAddress } = require("../utils/addressParser");
const { resolveAsset } = require("../utils/assets");

// const log = require("../utils/logger")("task:lido");

const snapLido = async () => {
  console.log(`\nLiquidity`);

  const armAddress = await parseAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", armAddress);

  const weth = await resolveAsset("WETH");
  const liquidityWeth = await weth.balanceOf(armAddress);

  const steth = await resolveAsset("STETH");
  const liquiditySteth = await steth.balanceOf(armAddress);
  const liquidityLidoWithdraws = await lidoARM.outstandingEther();

  const total = liquidityWeth + liquiditySteth + liquidityLidoWithdraws;
  const wethPercent = total == 0 ? 0 : (liquidityWeth * 10000n) / total;
  const stethWithdrawsPercent =
    total == 0 ? 0 : (liquidityLidoWithdraws * 10000n) / total;
  const oethPercent = total == 0 ? 0 : (liquiditySteth * 10000n) / total;

  console.log(
    `${formatUnits(liquidityWeth, 18)} WETH  ${formatUnits(wethPercent, 2)}%`
  );
  console.log(
    `${formatUnits(liquiditySteth, 18)} stETH ${formatUnits(oethPercent, 2)}%`
  );
  console.log(
    `${formatUnits(
      liquidityLidoWithdraws,
      18
    )} Lido withdrawal requests ${formatUnits(stethWithdrawsPercent, 2)}%`
  );
  console.log(`${formatUnits(total, 18)} total WETH and stETH`);
};

module.exports = {
  snapLido,
};
