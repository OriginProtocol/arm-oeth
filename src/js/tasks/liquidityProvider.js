const { parseUnits } = require("ethers");

const { getSigner } = require("../utils/signers");
const { parseDeployedAddress } = require("../utils/addressParser");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:lpCap");

async function depositLido({ amount }) {
  const signer = await getSigner();

  const amountBn = parseUnits(amount.toString());

  const lidArmAddress = await parseDeployedAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", lidArmAddress);

  log(`About to deposit ${amount} WETH to the Lido ARM`);
  const tx = await lidoARM.connect(signer).deposit(amountBn);
  await logTxDetails(tx, "deposit");
}

async function requestRedeemLido({ amount }) {
  const signer = await getSigner();

  const amountBn = parseUnits(amount.toString());

  const lidArmAddress = await parseDeployedAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", lidArmAddress);

  log(`About to request a redeem of ${amount} Lido ARM LP tokens`);
  const tx = await lidoARM.connect(signer).requestRedeem(amountBn);
  await logTxDetails(tx, "requestRedeem");
}

async function claimRedeemLido({ id }) {
  const signer = await getSigner();

  const lidArmAddress = await parseDeployedAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", lidArmAddress);

  log(`About to claim request with id ${id} from the Lido ARM`);
  const tx = await lidoARM.connect(signer).claimRedeem(id);
  await logTxDetails(tx, "claimRedeem");
}

async function setLiquidityProviderCaps({ accounts, cap }) {
  const signer = await getSigner();

  const capBn = parseUnits(cap.toString());

  const liquidityProviders = accounts.split(",");

  const lpcAddress = await parseDeployedAddress("LIDO_ARM_LPC");
  const liquidityProviderController = await ethers.getContractAt(
    "LiquidityProviderController",
    lpcAddress
  );

  log(
    `About to set deposit cap of ${cap} WETH for liquidity providers ${liquidityProviders}`
  );
  const tx = await liquidityProviderController
    .connect(signer)
    .setLiquidityProviderCaps(liquidityProviders, capBn);
  await logTxDetails(tx, "setLiquidityProviderCaps");
}

async function setTotalAssetsCap({ cap }) {
  const signer = await getSigner();

  const capBn = parseUnits(cap.toString());

  const lpcAddress = await parseDeployedAddress("LIDO_ARM_LPC");
  const liquidityProviderController = await ethers.getContractAt(
    "LiquidityProviderController",
    lpcAddress
  );

  log(`About to set total asset cap of ${cap} WETH`);
  const tx = await liquidityProviderController
    .connect(signer)
    .setTotalAssetsCap(capBn);
  await logTxDetails(tx, "setTotalAssetsCap");
}

module.exports = {
  depositLido,
  requestRedeemLido,
  claimRedeemLido,
  setLiquidityProviderCaps,
  setTotalAssetsCap,
};
