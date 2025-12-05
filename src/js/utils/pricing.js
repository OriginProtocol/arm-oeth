const { formatUnits, parseUnits } = require("ethers");

const log = require("../utils/logger")("task:utils:pricing");

const rangeSellPrice = (targetSellPrice, minSellPrice, maxSellPrice) => {
  log(
    `Adjusting target sell price ${formatUnits(targetSellPrice, 36)} based on min/max limits:`,
  );

  if (maxSellPrice) {
    const maxSellPriceBN = parseUnits(maxSellPrice.toString(), 36);
    if (targetSellPrice > maxSellPriceBN) {
      log(
        `target sell price ${formatUnits(
          targetSellPrice,
          36,
        )} is above max sell price ${maxSellPrice} so will use max`,
      );
      targetSellPrice = maxSellPriceBN;
    }
  }
  if (minSellPrice) {
    const minSellPriceBN = parseUnits(minSellPrice.toString(), 36);
    if (targetSellPrice < minSellPriceBN) {
      log(
        `target sell price ${formatUnits(
          targetSellPrice,
          36,
        )} is below min sell price ${minSellPrice} so will use min`,
      );
      targetSellPrice = minSellPriceBN;
    }
  }

  return targetSellPrice;
};

const rangeBuyPrice = (targetBuyPrice, minBuyPrice, maxBuyPrice) => {
  log(
    `Adjusting target buy price ${formatUnits(
      targetBuyPrice,
      36,
    )} based on min/max limits:`,
  );

  if (maxBuyPrice) {
    const maxBuyPriceBN = parseUnits(maxBuyPrice.toString(), 36);
    if (targetBuyPrice > maxBuyPriceBN) {
      log(
        `target buy price ${formatUnits(
          targetBuyPrice,
          36,
        )} is above max buy price ${maxBuyPrice} so will use max`,
      );
      targetBuyPrice = maxBuyPriceBN;
    }
  }
  if (minBuyPrice) {
    const minBuyPriceBN = parseUnits(minBuyPrice.toString(), 36);
    if (targetBuyPrice < minBuyPriceBN) {
      log(
        `target buy price ${formatUnits(
          targetBuyPrice,
          36,
        )} is below min buy price ${minBuyPrice} so will use min`,
      );
      targetBuyPrice = minBuyPriceBN;
    }
  }

  return targetBuyPrice;
};

module.exports = {
  rangeSellPrice,
  rangeBuyPrice,
};
