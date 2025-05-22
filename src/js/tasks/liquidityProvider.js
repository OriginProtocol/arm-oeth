const { parseUnits } = require("ethers");

const { getSigner } = require("../utils/signers");
const { parseDeployedAddress } = require("../utils/addressParser");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:lpCap");

async function depositARM({ amount, asset, arm }) {
  const signer = await getSigner();

  const amountBn = parseUnits(amount.toString());

  if (asset == "WETH") {
    const armAddress = await parseDeployedAddress(`${arm.toUpperCase()}_ARM`);
    const armContract = await ethers.getContractAt(
      `${arm.toUpperCase()}ARM`,
      armAddress
    );

    log(`About to deposit ${amount} WETH to the ${arm} ARM`);
    const tx = await armContract.connect(signer).deposit(amountBn);
    await logTxDetails(tx, "deposit");
  } else if (asset == "ETH") {
    const zapperAddress = await parseDeployedAddress("LIDO_ARM_ZAPPER");
    const zapper = await ethers.getContractAt("ZapperLidoARM", zapperAddress);

    log(`About to deposit ${amount} ETH to the Lido ARM via the Zapper`);
    const tx = await zapper.connect(signer).deposit({ value: amountBn });
    await logTxDetails(tx, "zap deposit");
  } else if (asset == "WS") {
    const armAddress = await parseDeployedAddress(`${arm.toUpperCase()}_ARM`);
    const armContract = await ethers.getContractAt(
      `${arm.toUpperCase()}ARM`,
      armAddress
    );

    log(`About to deposit ${amount} ${asset} to the ${arm} ARM`);
    const tx = await armContract.connect(signer).deposit(amountBn);
    await logTxDetails(tx, "deposit");
  } else if (asset == "S") {
    const zapperAddress = await parseDeployedAddress(
      `${arm.toUpperCase()}_ARM_ZAPPER`
    );
    const zapper = await ethers.getContractAt("ZapperARM", zapperAddress);
    const armAddress = await parseDeployedAddress(`${arm.toUpperCase()}_ARM`);

    log(`About to deposit ${amount} S to the ${arm} ARM via the Zapper`);
    const tx = await zapper
      .connect(signer)
      .deposit(armAddress, { value: amountBn });
    await logTxDetails(tx, "zap deposit");
  }
}

async function requestRedeemLido({ amount }) {
  const signer = await getSigner();

  const amountBn = parseUnits(amount.toString());

  const lidoArmAddress = await parseDeployedAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", lidoArmAddress);

  log(`About to request a redeem of ${amount} Lido ARM LP tokens`);
  const tx = await lidoARM.connect(signer).requestRedeem(amountBn);
  await logTxDetails(tx, "requestRedeem");
}

async function claimRedeemLido({ id }) {
  const signer = await getSigner();

  const lidoArmAddress = await parseDeployedAddress("LIDO_ARM");
  const lidoARM = await ethers.getContractAt("LidoARM", lidoArmAddress);

  log(`About to claim request with id ${id} from the Lido ARM`);
  const tx = await lidoARM.connect(signer).claimRedeem(id);
  await logTxDetails(tx, "claimRedeem");
}

async function setLiquidityProviderCaps({ accounts, cap }) {
  const signer = await getSigner();

  const capBn = parseUnits(cap.toString());

  const liquidityProviders = accounts.split(",");

  const lpcAddress = await parseDeployedAddress("LIDO_ARM_CAP_MAN");
  const capManager = await ethers.getContractAt("CapManager", lpcAddress);

  log(
    `About to set deposit cap of ${cap} WETH for liquidity providers ${liquidityProviders}`
  );
  const tx = await capManager
    .connect(signer)
    .setLiquidityProviderCaps(liquidityProviders, capBn);
  await logTxDetails(tx, "setLiquidityProviderCaps");
}

async function setTotalAssetsCap({ cap }) {
  const signer = await getSigner();

  const capBn = parseUnits(cap.toString());

  const lpcAddress = await parseDeployedAddress("LIDO_ARM_CAP_MAN");
  const capManager = await ethers.getContractAt("CapManager", lpcAddress);

  log(`About to set total asset cap of ${cap} WETH`);
  const tx = await capManager.connect(signer).setTotalAssetsCap(capBn);
  await logTxDetails(tx, "setTotalAssetsCap");
}

module.exports = {
  depositARM,
  requestRedeemLido,
  claimRedeemLido,
  setLiquidityProviderCaps,
  setTotalAssetsCap,
};
