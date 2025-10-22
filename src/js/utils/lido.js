const { ethers } = require("ethers");
const { mainnet } = require("./addresses");
const erc20Abi = require("../../abis/ERC20.json");

const getLidoQueueData = async (signer, blockTag) => {
  // This needs to work in a Defender Action so can't use resolveAsset which uses Hardhat's getContractAt
  const stETH = new ethers.Contract(mainnet.stETH, erc20Abi, signer);

  // get stETH in the withdrawal queue
  const withdrawals = await stETH.balanceOf(mainnet.lidoWithdrawalQueue, {
    blockTag,
  });

  // Get Lido deposits
  const deposits = await signer.provider.getBalance(
    stETH.getAddress(),
    blockTag,
  );

  // Get execution rewards
  const elRewards = await signer.provider.getBalance(
    mainnet.lidoExecutionLayerVault,
    blockTag,
  );

  // Get ETH swept from exited validators
  const ethFromValidators = await signer.provider.getBalance(
    mainnet.lidoWithdrawalManager,
    blockTag,
  );

  const finalization = deposits + elRewards + ethFromValidators;
  const outstanding = withdrawals - finalization;

  return {
    withdrawals,
    deposits,
    elRewards,
    ethFromValidators,
    finalization,
    outstanding,
  };
};

module.exports = { getLidoQueueData };
