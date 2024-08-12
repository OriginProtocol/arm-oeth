const { parseUnits } = require("ethers");

const { resolveAsset } = require("../utils/assets");
const { getSigner } = require("../utils/signers");
const { logTxDetails } = require("../utils/txLogger");
const { parseAddress } = require("../utils/addressParser");

const log = require("../utils/logger")("task:vault");

async function addWithdrawalQueueLiquidity() {
  const signer = await getSigner();

  const vaultAddress = await parseAddress("OETH_VAULT");
  const vault = await ethers.getContractAt("IOETHVault", vaultAddress);

  log(`About to call addWithdrawalQueueLiquidity() on the OETH Vault`);
  const tx = await vault.connect(signer).addWithdrawalQueueLiquidity();
  await logTxDetails(tx, "addWithdrawalQueueLiquidity");
}

async function allocate() {
  const signer = await getSigner();

  const vaultAddress = await parseAddress("OETH_VAULT");
  const vault = await ethers.getContractAt("IOETHVault", vaultAddress);

  log(`About to allocate the OETH Vault`);
  const tx = await vault.connect(signer).allocate();
  await logTxDetails(tx, "allocate");
}

async function rebase() {
  const signer = await getSigner();

  const vaultAddress = await parseAddress("OETH_VAULT");
  const vault = await ethers.getContractAt("IOETHVault", vaultAddress);

  log(`About to rebase the OETH Vault`);
  const tx = await vault.connect(signer).rebase();
  await logTxDetails(tx, "harvest");
}

/**
 * Call the Vault's admin pauseCapital method.
 */
async function capital({ pause }) {
  log("Setting Vault capitalPause to", pause);

  const sGovernor = await getSigner();

  const vaultAddress = await parseAddress("OETH_VAULT");
  const vault = await ethers.getContractAt("IOETHVault", vaultAddress);

  if (pause) {
    const tx = await vault.connect(sGovernor).pauseCapital();
    await logTxDetails(tx, "pauseCapital");
  } else {
    const tx = await vault.connect(sGovernor).unpauseCapital();
    await logTxDetails(tx, "unpauseCapital");
  }
}

async function mint({ amount, asset, min, approve }) {
  const signer = await getSigner();

  const vaultAddress = await parseAddress("OETH_VAULT");
  const vault = await ethers.getContractAt("IOETHVault", vaultAddress);

  const cAsset = await resolveAsset(asset);
  const assetUnits = parseUnits(amount.toString(), await cAsset.decimals());
  const minUnits = parseUnits(min.toString());

  if (approve) {
    const approveTx = await cAsset
      .connect(signer)
      .approve(vault.getAddress(), assetUnits);
    await logTxDetails(approveTx, "approve");
  }

  log(`About to mint OETH from ${amount} ${asset}`);
  const tx = await vault
    .connect(signer)
    .mint(cAsset.getAddress(), assetUnits, minUnits);
  await logTxDetails(tx, "mint");
}

async function redeem({ amount, min, symbol }) {
  const signer = await getSigner();

  const vaultAddress = await parseAddress("OETH_VAULT");
  const vault = await ethers.getContractAt("IOETHVault", vaultAddress);

  const oTokenUnits = parseUnits(amount.toString());
  const minUnits = parseUnits(min.toString());

  log(`About to redeem ${amount} ${symbol}`);
  const tx = await vault.connect(signer).redeem(oTokenUnits, minUnits);
  await logTxDetails(tx, "redeem");
}

async function redeemAll({ min, symbol }) {
  const signer = await getSigner();

  const vaultAddress = await parseAddress("OETH_VAULT");
  const vault = await ethers.getContractAt("IOETHVault", vaultAddress);

  const minUnits = parseUnits(min.toString());

  log(`About to redeem all ${symbol} tokens`);
  const tx = await vault.connect(signer).redeemAll(minUnits);
  await logTxDetails(tx, "redeemAll");
}

async function requestWithdrawal({ amount, symbol }) {
  const signer = await getSigner();

  const oTokenUnits = parseUnits(amount.toString());

  const vaultAddress = await parseAddress("OETH_VAULT");
  const vault = await ethers.getContractAt("IOETHVault", vaultAddress);

  // Get the withdrawal request ID by statically calling requestWithdrawal
  const { requestId } = await vault
    .connect(signer)
    .callStatic.requestWithdrawal(oTokenUnits);

  log(`About to request withdrawal from the ${symbol} vault`);
  const tx = await vault.connect(signer).requestWithdrawal(oTokenUnits);
  await logTxDetails(tx, "requestWithdrawal");

  console.log(`Withdrawal request id: ${requestId}`);
}

async function claimWithdrawal({ requestId, symbol }) {
  const signer = await getSigner();

  const vaultAddress = await parseAddress("OETH_VAULT");
  const vault = await ethers.getContractAt("IOETHVault", vaultAddress);

  log(
    `About to claim withdrawal from the ${symbol} vault for request ${requestId}`
  );
  const tx = await vault.connect(signer).claimWithdrawal(requestId);
  await logTxDetails(tx, "claimWithdrawal");
}

module.exports = {
  addWithdrawalQueueLiquidity,
  allocate,
  capital,
  mint,
  rebase,
  redeem,
  redeemAll,
  requestWithdrawal,
  claimWithdrawal,
};
