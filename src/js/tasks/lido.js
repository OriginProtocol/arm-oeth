const { formatUnits, parseUnits, MaxInt256 } = require("ethers");

const addresses = require("../utils/addresses");
const {
  logArmPrices,
  log1InchPrices,
  logCurvePrices,
  logUniswapSpotPrices,
} = require("./markets");
const { getBlock } = require("../utils/block");
const { getLidoQueueData } = require("../utils/lido");
const { getSigner } = require("../utils/signers");
const { logTxDetails } = require("../utils/txLogger");
const {
  parseAddress,
  parseDeployedAddress,
} = require("../utils/addressParser");
const { resolveAddress, resolveAsset } = require("../utils/assets");

const log = require("../utils/logger")("task:lido");

const lidoWithdrawStatus = async ({ block, id }) => {
  const blockTag = await getBlock(block);
  const lidoWithdrawalQueueAddress = await parseAddress("LIDO_WITHDRAWAL");
  const stEthWithdrawQueue = await hre.ethers.getContractAt(
    "IStETHWithdrawal",
    lidoWithdrawalQueueAddress
  );

  const status = await stEthWithdrawQueue.getWithdrawalStatus([id], {
    blockTag,
  });

  console.log(
    `Withdrawal request ${id} for ${formatUnits(
      status[0].amountOfStETH
    )} stETH is finalized ${status[0].isFinalized} and claimed ${
      status[0].isClaimed
    }`
  );
};

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

const snapLido = async ({
  amount,
  block,
  curve,
  oneInch,
  uniswap,
  gas,
  queue,
  lido,
  user,
  cap,
}) => {
  const blockTag = await getBlock(block);
  const signer = await getSigner();
  const commonOptions = { amount, blockTag, pair: "stETH/ETH", gas, signer };

  const armAddress = await parseAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", armAddress);
  const capManagerAddress = await parseDeployedAddress("LIDO_ARM_CAP_MAN");
  const capManager = await ethers.getContractAt(
    "CapManager",
    capManagerAddress
  );

  const { totalAssets, totalSupply, liquidityWeth } = await logAssets(
    lidoARM,
    blockTag
  );
  if (lido) {
    await logLidoQueue(signer, blockTag);

    await logLidoWithdrawals(lidoARM, blockTag);
  }
  if (queue) {
    await logWithdrawalQueue(lidoARM, blockTag, liquidityWeth);
  }
  if (user) {
    await logUser(lidoARM, capManager, blockTag, totalSupply);
  }
  if (cap) {
    await logCaps(capManager, totalAssets, blockTag);
  }

  const ammPrices = await logArmPrices(commonOptions, lidoARM);

  if (uniswap) {
    await logUniswapSpotPrices(commonOptions, ammPrices);
  }

  if (curve) {
    await logCurvePrices(
      {
        ...commonOptions,
        poolName: "NextGen",
        poolAddress: addresses.mainnet.CurveNgStEthPool,
      },
      ammPrices
    );

    await logCurvePrices(
      {
        ...commonOptions,
        poolName: "Old",
        poolAddress: addresses.mainnet.CurveStEthPool,
      },
      ammPrices
    );
  }

  if (oneInch) {
    await log1InchPrices(commonOptions, ammPrices);
  }
};

const logLidoWithdrawals = async (lidoARM, blockTag) => {
  const lidoWithdrawalQueueAddress = await parseAddress("LIDO_WITHDRAWAL");
  const stEthWithdrawQueue = await hre.ethers.getContractAt(
    "IStETHWithdrawal",
    lidoWithdrawalQueueAddress
  );
  const outstandingRequests = await stEthWithdrawQueue.getWithdrawalRequests(
    lidoARM.getAddress(),
    { blockTag }
  );

  console.log(
    `\n${outstandingRequests.length} Lido withdrawal requests: ${outstandingRequests}`
  );
};

const logLidoQueue = async (signer, blockTag) => {
  const {
    withdrawals,
    deposits,
    elRewards,
    ethFromValidators,
    finalization,
    outstanding,
  } = await getLidoQueueData(signer, blockTag);

  console.log(`\nLido withdrawal queue`);
  console.log(`${formatUnits(withdrawals, 18).padEnd(24)} stETH withdrawals`);
  console.log(`${formatUnits(deposits, 18).padEnd(24)} ETH from deposits`);
  console.log(
    `${formatUnits(elRewards, 18).padEnd(24)} ETH from execution rewards`
  );
  console.log(
    `${formatUnits(ethFromValidators, 18).padEnd(24)} ETH from validators`
  );
  console.log(
    `${formatUnits(finalization, 18).padEnd(24)} ETH to be finalized`
  );
  console.log(`${formatUnits(outstanding, 18).padEnd(24)} ETH outstanding`);
};

const logCaps = async (capManager, totalAssets, blockTag) => {
  const totalAssetsCap = await capManager.totalAssetsCap({ blockTag });
  const capRemaining = totalAssetsCap - totalAssets;
  const capUsedPercent = (totalAssets * 10000n) / totalAssetsCap;

  console.log(`\nCaps`);
  console.log(
    `${formatUnits(totalAssetsCap, 18)} total assets cap, ${formatUnits(
      capUsedPercent,
      2
    )}% used, ${formatUnits(capRemaining, 18)} remaining`
  );
};

const logUser = async (arm, capManager, blockTag, totalSupply) => {
  const user = await getSigner();
  console.log(`\nUser ${await user.getAddress()}`);

  const shares = await arm.balanceOf(user.getAddress(), { blockTag });
  const sharesPercentage = (shares * 10000n) / totalSupply;
  const userCap = await capManager.liquidityProviderCaps(user.getAddress(), {
    blockTag,
  });

  console.log(
    `${formatUnits(shares, 18)} shares (${formatUnits(sharesPercentage, 2)}%)`
  );
  console.log(`${formatUnits(userCap, 18)} cap remaining`);
};

const logWithdrawalQueue = async (arm, blockTag, liquidityWeth) => {
  const queue = await arm.withdrawsQueued({
    blockTag,
  });
  const claimed = await arm.withdrawsClaimed({ blockTag });
  const outstanding = queue - claimed;
  const shortfall =
    liquidityWeth < outstanding ? liquidityWeth - outstanding : 0;

  console.log(`\nARM Withdrawal Queue`);
  console.log(`${formatUnits(outstanding, 18).padEnd(23)} outstanding`);
  console.log(`${formatUnits(shortfall, 18).padEnd(23)} shortfall`);
};

const logAssets = async (arm, blockTag) => {
  const armBuybackAddress = await parseAddress("ARM_BUYBACK");
  const weth = await resolveAsset("WETH");
  const liquidityWeth = await weth.balanceOf(arm.getAddress(), { blockTag });
  const armBuybackWeth = await weth.balanceOf(armBuybackAddress, { blockTag });

  const steth = await resolveAsset("STETH");
  const liquiditySteth = await steth.balanceOf(arm.getAddress(), { blockTag });
  const liquidityLidoWithdraws = await arm.lidoWithdrawalQueueAmount({
    blockTag,
  });

  const total = liquidityWeth + liquiditySteth + liquidityLidoWithdraws;
  const wethPercent = total == 0 ? 0 : (liquidityWeth * 10000n) / total;
  const stethWithdrawsPercent =
    total == 0 ? 0 : (liquidityLidoWithdraws * 10000n) / total;
  const oethPercent = total == 0 ? 0 : (liquiditySteth * 10000n) / total;
  const totalAssets = await arm.totalAssets({ blockTag });
  const totalSupply = await arm.totalSupply({ blockTag });
  const assetPerShare = await arm.convertToAssets(parseUnits("1"), {
    blockTag,
  });
  const feesAccrued = await arm.feesAccrued({ blockTag });
  const strategistAddress = await parseAddress("STRATEGIST");
  const wethInStrategist = await weth.balanceOf(strategistAddress, {
    blockTag,
  });

  console.log(`Assets`);
  console.log(
    `${formatUnits(liquidityWeth, 18).padEnd(24)} WETH  ${formatUnits(
      wethPercent,
      2
    )}%`
  );
  console.log(
    `${formatUnits(liquiditySteth, 18).padEnd(24)} stETH ${formatUnits(
      oethPercent,
      2
    )}%`
  );
  console.log(
    `${formatUnits(liquidityLidoWithdraws, 18).padEnd(
      24
    )} Lido withdraw ${formatUnits(stethWithdrawsPercent, 2)}%`
  );
  console.log(`${formatUnits(total, 18).padEnd(24)} Total WETH and stETH`);
  console.log(`${formatUnits(totalAssets, 18).padEnd(24)} Total assets`);
  console.log(`${formatUnits(totalSupply, 18).padEnd(24)} Total supply`);
  console.log(`${formatUnits(assetPerShare, 18).padEnd(24)} Asset per share`);
  console.log(
    `${formatUnits(feesAccrued, 18).padEnd(24)} Accrued performance fees`
  );
  console.log(
    `${formatUnits(wethInStrategist, 18).padEnd(24)} WETH in Strategist (fees)`
  );
  console.log(`${formatUnits(armBuybackWeth, 18).padEnd(24)} WETH in Buyback`);

  return { totalAssets, totalSupply, liquidityWeth };
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
  lidoWithdrawStatus,
  submitLido,
  swapLido,
  snapLido,
  setZapper,
};
