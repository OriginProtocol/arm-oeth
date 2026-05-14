const { formatUnits, parseUnits } = require("ethers");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");

const { getBlock } = require("../utils/block");
const { resolveArmContract } = require("../utils/addressParser");
const { logWithdrawalRequests } = require("../utils/etherFi");
const {
  logArmPrices,
  log1InchPrices,
  logKyberPrices,
  logWrappedEtherFiPrices,
} = require("./markets");
const { getMerklRewards } = require("../utils/merkl");
const { convertToAsset } = require("../utils/pricing");
const { logTxDetails } = require("../utils/txLogger");
const { getSigner } = require("../utils/signers");
const { adapterContract, resolveArmBase } = require("../utils/arm");

const log = require("../utils/logger")("task:liquidity");

// Extend Day.js with the UTC plugin
dayjs.extend(utc);

const requestWithdraw = async ({ amount, signer, arm, armName, base }) => {
  const amountBI = parseUnits(amount.toString(), 18);
  const { baseAddress, baseSymbol } = await resolveArmBase({
    arm,
    armName,
    base,
  });

  log(`About to request ${amount} ${baseSymbol} withdrawal`);

  const tx = await arm
    .connect(signer)
    .requestBaseAssetRedeem(baseAddress, amountBI);

  await logTxDetails(tx, "requestRedeem");

  // TODO parse the request id from the WithdrawalRequested event on the OETH Vault
};

const claimWithdraw = async ({ id, signer, arm, armName, base }) => {
  const { baseAddress, config } = await resolveArmBase({
    arm,
    armName,
    base,
  });
  const adapter = await adapterContract(config.adapter, signer);
  const shares = await adapter["requestShares(uint256)"](id);
  const tx = await arm
    .connect(signer)
    .claimBaseAssetRedeem(baseAddress, shares);

  log(`About to claim withdrawal request ${id}`);
  await logTxDetails(tx, "claimRedeem");
};

const withdrawRequestStatus = async ({ id, arm, vault }) => {
  const queue = await vault.withdrawalQueueMetadata();
  const request = await arm.withdrawalRequests(id);

  if (request.queued <= queue.claimable) {
    console.log(`Withdrawal request ${id} is claimable.`);
  } else {
    console.log(
      `Withdrawal request ${id} is ${formatUnits(
        request.queued - queue.claimable,
      )} short`,
    );
  }
};

const snap = async ({
  arm,
  block,
  days,
  gas,
  amount,
  oneInch,
  kyber,
  route,
  base,
}) => {
  const armContract = await resolveArmContract(arm);

  const { chainId } = await ethers.provider.getNetwork();

  const blockTag = await getBlock(block);

  const { liquidityBalance } = await logLiquidity({ arm, block, base });

  if (arm === "EtherFi") {
    await logWithdrawalRequests({ blockTag });
  }

  await logWithdrawalQueue(armContract, blockTag, liquidityBalance);

  const baseContext = await resolveArmBase({
    arm: armContract,
    armName: arm,
    base,
    blockTag,
  });
  const armPrices = await logArmPrices(
    { block, blockTag, gas, days, ...baseContext },
    armContract,
  );

  const pair =
    arm === "Lido"
      ? `${baseContext.baseSymbol}/WETH`
      : arm === "EtherFi"
        ? `${baseContext.baseSymbol}/WETH`
        : arm === "Ethena"
          ? `${baseContext.baseSymbol}/USDe`
          : arm == "Origin" && chainId === 146
            ? `${baseContext.baseSymbol}/wS`
            : `${baseContext.baseSymbol}/WETH`;
  const assets = {
    liquid: baseContext.liquidityAddress,
    base: baseContext.baseAddress,
  };

  let wrapPrice;
  if (arm === "Ethena") {
    const signer = await getSigner();
    wrapPrice = await convertToAsset(assets.base, amount, signer);
    const actualArmSellPrice =
      (armPrices.sellPrice * wrapPrice) / parseUnits("1", 18);
    const actualArmBuyPrice =
      (armPrices.buyPrice * wrapPrice) / parseUnits("1", 18);

    console.log(`\nEthena : ${formatUnits(wrapPrice, 18)} sUSDe/USDe`);
    console.log(
      `Sell   : ${formatUnits(actualArmSellPrice, 18).padEnd(20)} sUSDe/USDe`,
    );
    console.log(
      `Buy    : ${formatUnits(actualArmBuyPrice, 18).padEnd(20)} sUSDe/USDe`,
    );
  }

  if (oneInch) {
    const fee = arm === "Lido" ? 10n : 30n;

    await log1InchPrices(
      { amount, assets, fee, pair, chainId, wrapPrice, route },
      armPrices,
    );

    if (arm === "EtherFi") {
      await logWrappedEtherFiPrices({ amount, armPrices });
    }
  }

  if (kyber && chainId !== 146) {
    // Kyber does not support Sonic
    await logKyberPrices({ amount, assets, pair, wrapPrice, route }, armPrices);
  }
};

const logLiquidity = async ({ block, arm, base }) => {
  const blockTag = await getBlock(block);
  console.log(`\nLiquidity`);

  const armContract = await resolveArmContract(arm);
  const armAddress = await armContract.getAddress();

  const liquidityAddress = await armContract.liquidityAsset();
  const liquidAsset = await ethers.getContractAt(
    "IERC20Metadata",
    liquidityAddress,
  );
  const liquiditySymbol = await liquidAsset.symbol();
  const liquidityBalance = await liquidAsset.balanceOf(armAddress, {
    blockTag,
  });

  const { baseAddress, baseSymbol, config } = await resolveArmBase({
    arm: armContract,
    armName: arm,
    base,
    blockTag,
  });
  const baseAsset = await ethers.getContractAt("IERC20Metadata", baseAddress);
  const baseBalance = await baseAsset.balanceOf(armAddress, { blockTag });
  const baseBalanceAssets = config.peggedToLiquidityAsset
    ? baseBalance
    : await (
        await adapterContract(config.adapter, armContract.runner)
      ).convertToAssets(baseBalance);

  const baseWithdraws = config.pendingRedeemAssets;

  let lendingMarketBalance = 0n;
  let lendingMarketRedeemableBalance = 0n;
  let lendingMarketMaxWithdraw = 0n;
  let morphoRewards = 0n;
  // TODO this can be removed after OETH is upgraded
  if (arm !== "Oeth") {
    // Get the lending market from the active SiloMarket
    const marketAddress = await armContract.activeMarket({ blockTag });
    if (marketAddress !== ethers.ZeroAddress) {
      const market = await ethers.getContractAt(
        "Abstract4626MarketWrapper",
        marketAddress,
      );
      const armShares = await market.balanceOf(armAddress, { blockTag });
      lendingMarketBalance = await market.convertToAssets(armShares, {
        blockTag,
      });
      lendingMarketRedeemableBalance = await market.previewRedeem(armShares, {
        blockTag,
      });
      lendingMarketMaxWithdraw = await market.maxWithdraw(armAddress, {
        blockTag,
      });

      if (arm !== "Ethena") {
        const { amount } = await getMerklRewards({
          userAddress: marketAddress,
        });
        morphoRewards = amount;
      }
    }
  }

  const total =
    liquidityBalance + baseBalanceAssets + baseWithdraws + lendingMarketBalance;
  const liquidityPercent = total == 0 ? 0 : (liquidityBalance * 10000n) / total;
  const baseWithdrawsPercent =
    total == 0 ? 0 : (baseWithdraws * 10000n) / total;
  const basePercent = total == 0 ? 0 : (baseBalance * 10000n) / total;
  const lendingMarketPercent =
    total == 0 ? 0 : (lendingMarketBalance * 10000n) / total;

  const totalAssets = await armContract.totalAssets({ blockTag });
  const totalSupply = await armContract.totalSupply({ blockTag });
  const assetPerShare = await armContract.convertToAssets(parseUnits("1"), {
    blockTag,
  });
  const accruedFees = await armContract.feesAccrued({ blockTag });
  const buffer = await armContract.armBuffer({ blockTag });
  const bufferPercent = (buffer * 10000n) / parseUnits("1");
  const lendingMarketLiquidityShortfall =
    lendingMarketBalance - lendingMarketRedeemableBalance;

  console.log(
    `${formatUnits(liquidityBalance, 18)} ${liquiditySymbol} ${formatUnits(
      liquidityPercent,
      2,
    )}%`,
  );
  console.log(
    `${formatUnits(baseBalance, 18)} ${baseSymbol} ${formatUnits(
      basePercent,
      2,
    )}%`,
  );
  console.log(
    `${formatUnits(
      baseWithdraws,
      18,
    )} ${baseSymbol} in withdrawal requests ${formatUnits(
      baseWithdrawsPercent,
      2,
    )}%`,
  );
  console.log(
    `${formatUnits(
      lendingMarketBalance,
      18,
    )} ${liquiditySymbol} in active lending market ${formatUnits(
      lendingMarketPercent,
      2,
    )}%`,
  );
  console.log(
    `${formatUnits(
      lendingMarketRedeemableBalance,
      18,
    )} lending market previewRedeem`,
  );
  console.log(
    `${formatUnits(lendingMarketMaxWithdraw, 18)} lending market maxWithdraw`,
  );
  console.log(
    `${formatUnits(lendingMarketLiquidityShortfall, 18)} lending market liquidity shortfall`,
  );
  console.log(`${formatUnits(total, 18)} raw total assets`);

  console.log(`${formatUnits(accruedFees, 18)} accrued fees`);
  console.log(`${formatUnits(totalAssets, 18)} total assets`);
  console.log(`${formatUnits(totalSupply, 18)} total supply`);
  console.log(`${formatUnits(assetPerShare, 18)} asset per share`);
  console.log(`liquidity buffer ${formatUnits(bufferPercent, 2)}%`);
  console.log(`${formatUnits(morphoRewards, 18)} MORPHO rewards claimable`);

  return { total, liquidityBalance };
};

const logWithdrawalQueue = async (arm, blockTag, liquidityWeth) => {
  const queue = await arm.withdrawsQueued({
    blockTag,
  });
  const claimed = await arm.withdrawsClaimed({ blockTag });
  const outstanding = queue - claimed;
  const available = liquidityWeth - outstanding;

  console.log(`\nARM Withdrawal Queue`);
  console.log(`${formatUnits(outstanding, 18).padEnd(23)} outstanding`);
  console.log(`${formatUnits(available, 18).padEnd(23)} available`);
};

module.exports = {
  snap,
  logLiquidity,
  logWithdrawalQueue,
  requestWithdraw,
  claimWithdraw,
  withdrawRequestStatus,
};
