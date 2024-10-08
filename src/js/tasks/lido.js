const { formatUnits, parseUnits, MaxInt256 } = require("ethers");

const { getBlock } = require("../utils/block");
const { getSigner } = require("../utils/signers");
const { logTxDetails } = require("../utils/txLogger");
const {
  parseAddress,
  parseDeployedAddress,
} = require("../utils/addressParser");
const { resolveAddress, resolveAsset } = require("../utils/assets");

const log = require("../utils/logger")("task:lido");

const submitLido = async ({ amount }) => {
  const signer = await getSigner();

  const stethAddress = await parseAddress("STETH");
  //   const steth = await ethers.getContractAt("ISTETH", stethAddress);

  const etherAmount = parseUnits(amount.toString());

  log(`About to send ${amount} ETH to Lido's stETH`);
  const tx = await signer.sendTransaction({
    to: stethAddress,
    value: etherAmount,
  });
  //   const tx = await steth.connect(signer)({ value: etherAmount });
  await logTxDetails(tx, "submit");
};

const snapLido = async ({ block }) => {
  const blockTag = await getBlock(block);
  console.log(`\nLiquidity`);

  const armAddress = await parseAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", armAddress);
  const capManagerAddress = await parseDeployedAddress("LIDO_ARM_CAP_MAN");
  const capManager = await ethers.getContractAt(
    "CapManager",
    capManagerAddress
  );

  const weth = await resolveAsset("WETH");
  const liquidityWeth = await weth.balanceOf(armAddress, { blockTag });

  const steth = await resolveAsset("STETH");
  const liquiditySteth = await steth.balanceOf(armAddress, { blockTag });
  const liquidityLidoWithdraws = await lidoARM.lidoWithdrawalQueueAmount({
    blockTag,
  });

  const total = liquidityWeth + liquiditySteth + liquidityLidoWithdraws;
  const wethPercent = total == 0 ? 0 : (liquidityWeth * 10000n) / total;
  const stethWithdrawsPercent =
    total == 0 ? 0 : (liquidityLidoWithdraws * 10000n) / total;
  const oethPercent = total == 0 ? 0 : (liquiditySteth * 10000n) / total;
  const totalAssets = await lidoARM.totalAssets({ blockTag });
  const feesAccrued = await lidoARM.feesAccrued({ blockTag });
  const totalAssetsCap = await capManager.totalAssetsCap({ blockTag });
  const capRemaining = totalAssetsCap - totalAssets;
  const capUsedPercent = (totalAssets * 10000n) / totalAssetsCap;

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
  console.log(`${formatUnits(totalAssets, 18)} total assets`);
  console.log(
    `\n${formatUnits(totalAssetsCap, 18)} total assets cap, ${formatUnits(
      capUsedPercent,
      2
    )}% used, ${formatUnits(capRemaining, 18)} remaining`
  );
  console.log(`${formatUnits(feesAccrued, 18)} in accrued fees`);
};

const swapLido = async ({ from, to, amount }) => {
  if (from && to) {
    throw new Error(
      `Cannot specify both from and to asset. It has to be one or the other`
    );
  }
  const signer = await getSigner();
  const signerAddress = await signer.getAddress();

  const armAddress = await parseAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", armAddress);

  if (from) {
    const fromAddress = await resolveAddress(from.toUpperCase());

    const to = from === "stETH" ? "WETH" : "stETH";
    const toAddress = await resolveAddress(to.toUpperCase());

    const fromAmount = parseUnits(amount.toString(), 18);

    log(`About to swap ${amount} ${from} to ${to} for ${signerAddress}`);

    const tx = await lidoARM
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
    const from = to === "stETH" ? "WETH" : "stETH";
    const fromAddress = await resolveAddress(from.toUpperCase());

    const toAddress = await resolveAddress(to.toUpperCase());

    const toAmount = parseUnits(amount.toString(), 18);

    log(`About to swap ${from} to ${amount} ${to} for ${signerAddress}`);

    const tx = await lidoARM
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

module.exports = {
  submitLido,
  swapLido,
  snapLido,
};
