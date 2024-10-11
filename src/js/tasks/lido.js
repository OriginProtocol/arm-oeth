const { formatUnits, parseUnits, MaxInt256 } = require("ethers");

const addresses = require("../utils/addresses");
const {
  logArmPrices,
  log1InchPrices,
  logCurvePrices,
  logUniswapSpotPrices,
} = require("./markets");
const { getBlock } = require("../utils/block");
const { getSigner } = require("../utils/signers");
const { logTxDetails } = require("../utils/txLogger");
const {
  parseAddress,
  parseDeployedAddress,
} = require("../utils/addressParser");
const { resolveAddress, resolveAsset } = require("../utils/assets");

const log = require("../utils/logger")("task:lido");

async function collectFees() {
  const signer = await getSigner();

  const lidoArmAddress = await parseDeployedAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", lidoArmAddress);

  log(`About to collect fees from the Lido ARM`);
  const tx = await lidoARM.connect(signer).collectFees();
  await logTxDetails(tx, "collectFees");
}

async function requestLidoWithdrawals({ amount }) {
  const signer = await getSigner();

  const lidoArmAddress = await parseDeployedAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", lidoArmAddress);

  const amountBI = parseUnits(amount.toString(), 18);

  log(`About to request the withdrawal of ${amount} stETH from Lido`);
  const tx = await lidoARM.connect(signer).requestLidoWithdrawals([amountBI]);
  await logTxDetails(tx, "requestLidoWithdrawals");
}

async function claimLidoWithdrawals({ id }) {
  const signer = await getSigner();

  const lidoArmAddress = await parseDeployedAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", lidoArmAddress);

  log(`About to claim the withdrawal with ${id} from Lido`);
  const tx = await lidoARM.connect(signer).claimLidoWithdrawals([id]);
  await logTxDetails(tx, "claimLidoWithdrawals");
}

async function setZapper() {
  const signer = await getSigner();

  const lidoArmAddress = await parseDeployedAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", lidoArmAddress);

  const zapperAddress = await parseDeployedAddress("LIDO_ARM_ZAPPER");

  log(`About to set the Zapper contract on the Lido ARM to ${zapperAddress}`);
  const tx = await lidoARM.connect(signer).setZap(zapperAddress);
  await logTxDetails(tx, "setZap");
}

const lidoWithdrawStatus = async ({ id }) => {
  const lidoWithdrawalQueueAddress = await parseAddress("LIDO_WITHDRAWAL");
  const stEthWithdrawQueue = await hre.ethers.getContractAt(
    "IStETHWithdrawal",
    lidoWithdrawalQueueAddress
  );

  const status = await stEthWithdrawQueue.getWithdrawalStatus([id]);

  console.log(
    `Withdrawal request ${id} is finalized ${status[0].isFinalized} and claimed ${status[0].isClaimed}`
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

const snapLido = async ({ amount, block, curve, oneInch, uniswap }) => {
  const blockTag = await getBlock(block);
  const pair = "stETH/ETH";

  const armAddress = await parseAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", armAddress);
  const capManagerAddress = await parseDeployedAddress("LIDO_ARM_CAP_MAN");
  const capManager = await ethers.getContractAt(
    "CapManager",
    capManagerAddress
  );

  const ammPrices = await logArmPrices(lidoARM, blockTag);

  if (oneInch) {
    await log1InchPrices(amount, ammPrices);
  }

  if (curve) {
    await logCurvePrices(
      {
        blockTag,
        amount,
        pair,
        poolName: "Old",
        poolAddress: addresses.mainnet.CurveStEthPool,
      },
      ammPrices
    );

    await logCurvePrices(
      {
        blockTag,
        amount,
        pair,
        poolName: "NextGen",
        poolAddress: addresses.mainnet.CurveNgStEthPool,
      },
      ammPrices
    );
  }

  if (uniswap) {
    await logUniswapSpotPrices({ blockTag, pair, amount }, ammPrices);
  }

  const { totalAssets, totalSupply, liquidityWeth } = await logAssets(
    lidoARM,
    blockTag
  );
  await logWithdrawalQueue(lidoARM, blockTag, liquidityWeth);
  await logUser(lidoARM, capManager, blockTag, totalSupply);

  const feesAccrued = await lidoARM.feesAccrued({ blockTag });
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
  console.log(`${formatUnits(feesAccrued, 18)} in accrued performance fees`);
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
  console.log(`${formatUnits(outstanding, 18)} outstanding`);
  console.log(`${formatUnits(shortfall, 18)} shortfall`);
};

const logAssets = async (arm, blockTag) => {
  const weth = await resolveAsset("WETH");
  const liquidityWeth = await weth.balanceOf(arm.getAddress(), { blockTag });

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

  console.log(`\nAssets`);
  console.log(
    `${formatUnits(liquidityWeth, 18).padEnd(23)} WETH  ${formatUnits(
      wethPercent,
      2
    )}%`
  );
  console.log(
    `${formatUnits(liquiditySteth, 18).padEnd(23)} stETH ${formatUnits(
      oethPercent,
      2
    )}%`
  );
  console.log(
    `${formatUnits(liquidityLidoWithdraws, 18).padEnd(
      23
    )} Lido withdraw ${formatUnits(stethWithdrawsPercent, 2)}%`
  );
  console.log(`${formatUnits(total, 18).padEnd(23)} total WETH and stETH`);
  console.log(`${formatUnits(totalAssets, 18).padEnd(23)} total assets`);
  console.log(`${formatUnits(totalSupply, 18).padEnd(23)} total supply`);
  console.log(`${formatUnits(assetPerShare, 18).padEnd(23)} asset per share`);

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
  collectFees,
  requestLidoWithdrawals,
  claimLidoWithdrawals,
  lidoWithdrawStatus,
  submitLido,
  swapLido,
  snapLido,
  setZapper,
};
