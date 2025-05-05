const { ethers } = require("ethers");
const { formatUnits, parseUnits } = require("ethers");

const interestRateModelAbi = require("../../abis/SiloInterestRateModelV2.json");
const siloAbi = require("../../abis/Silo.json");
const siloConfigAbi = require("../../abis/SiloConfig.json");
const { getBlock, getBlockTimestamp } = require("../utils/block");
const { getSigner } = require("../utils/signers");
const { parseAddress } = require("../utils/addressParser");

const log = require("../utils/logger")("task:silo");

async function snapSiloMarkets({ block }) {
  const blockTag = await getBlock(block);
  const timestamp = await getBlockTimestamp(blockTag);

  const interestRateModelAddress = await parseAddress("INTEREST_RATE_MODEL");

  const signer = await getSigner();
  const interestRateModel = new ethers.Contract(
    interestRateModelAddress,
    interestRateModelAbi,
    signer
  );
  log(
    `SiloInterestRateModel contract address: ${await interestRateModel.getAddress()}`
  );

  const markets = [
    "0x112380065A2cb73A5A429d9Ba7368cc5e8434595", // wS paired with OS
    "0x47d8490Be37ADC7Af053322d6d779153689E13C1", // wS paired with stS
    "0xf55902DE87Bd80c6a35614b48d7f8B612a083C12", // wS paired with USDC https://v2.silo.finance/markets/sonic/s-usdc-20
  ];
  for (const marketAddress of markets) {
    await snapSiloMarket(
      interestRateModel,
      marketAddress,
      timestamp,
      blockTag,
      signer
    );
  }
}

async function snapSiloMarket(
  interestRateModel,
  marketAddress,
  timestamp,
  blockTag,
  signer
) {
  const siloMarket = new ethers.Contract(marketAddress, siloAbi, signer);
  const marketSymbol = await siloMarket.symbol();
  const utilizationData = await siloMarket.utilizationData({ blockTag });
  const interestModelConfigArray = await interestRateModel.getConfig(
    marketAddress,
    {
      blockTag,
    }
  );
  const interestModelConfig = {
    uopt: interestModelConfigArray[0],
    ucrit: interestModelConfigArray[1],
    ulow: interestModelConfigArray[2],
    ki: interestModelConfigArray[3],
    kcrit: interestModelConfigArray[4],
    klow: interestModelConfigArray[5],
    klin: interestModelConfigArray[6],
    beta: interestModelConfigArray[7],
    ri: interestModelConfigArray[8],
    Tcrit: interestModelConfigArray[9],
  };
  //   log(`Silo interest model config: ${interestModelConfigArray}`);

  const calculatedInterestRate =
    await interestRateModel.calculateCurrentInterestRate(
      interestModelConfig,
      utilizationData[0], // collateralAssets,
      utilizationData[1], // debtAssets,
      utilizationData[2], // interestRateTimestamp,
      timestamp,
      {
        blockTag,
      }
    );

  const configAddress = await siloMarket.config();
  const siloConfig = new ethers.Contract(configAddress, siloConfigAbi, signer);
  const siloConfigData = await siloConfig.getConfig(marketAddress, {
    blockTag,
  });
  const fee = siloConfigData[0];
  //   log(`Silo config: ${siloConfigData}`);

  const borrowInterestRate = calculatedInterestRate / parseUnits("1", 14);
  const utilization = (utilizationData[1] * 10000n) / utilizationData[0];
  // Deposit APR = Borrowing APR × Utilization × (1 − Protocol Fee)
  const depositInterestRate =
    (calculatedInterestRate *
      utilizationData[1] *
      10000n *
      (parseUnits("1") - fee)) /
    (utilizationData[0] * parseUnits("1", 36));

  log(
    `${marketSymbol.padStart(6)} deposit ${formatUnits(
      depositInterestRate,
      2
    ).padStart(5)}%, borrow ${formatUnits(
      borrowInterestRate,
      2
    ).padStart(5)}%, utilization: ${formatUnits(utilization, 2).padStart(5)}%`
  );
}

module.exports = {
  snapSiloMarkets,
};
