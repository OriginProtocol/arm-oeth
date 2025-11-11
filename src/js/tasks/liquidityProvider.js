const { parseUnits } = require("ethers");

const { getSigner } = require("../utils/signers");
const {
  parseDeployedAddress,
  resolveArmContract,
} = require("../utils/addressParser");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:lpCap");

async function depositARM({ amount, asset, arm }) {
  const signer = await getSigner();

  const amountBn = parseUnits(amount.toString());

  const armContract = await resolveArmContract(arm);

  if (asset == "WETH") {
    log(`About to deposit ${amount} WETH to the ${arm} ARM`);
    const tx = await armContract.connect(signer).deposit(amountBn);
    await logTxDetails(tx, "deposit");
  } else if (asset == "ETH") {
    const zapperAddress = await parseDeployedAddress("ARM_ZAPPER");
    const zapper = await ethers.getContractAt("ZapperARM", zapperAddress);

    const armAddress = await armContract.getAddress();

    log(`About to deposit ${amount} ETH to ARM ${armAddress} via the Zapper`);
    const tx = await zapper
      .connect(signer)
      .deposit(armAddress, { value: amountBn });
    await logTxDetails(tx, "zap deposit");
  } else if (asset == "WS") {
    const armAddress = await parseDeployedAddress(`${arm.toUpperCase()}_ARM`);
    const armContract = await ethers.getContractAt(`${arm}ARM`, armAddress);

    // Add 10% buffer to gas limit
    let gasLimit = await armContract
      .connect(signer)
      ["deposit(uint256)"].estimateGas(amountBn);
    gasLimit = (gasLimit * 11n) / 10n;

    log(`About to deposit ${amount} ${asset} to the ${arm} ARM`);
    const tx = await armContract
      .connect(signer)
      ["deposit(uint256)"](amountBn, { gasLimit });
    await logTxDetails(tx, "deposit");
  } else if (asset == "S") {
    const zapperAddress = await parseDeployedAddress(
      `${arm.toUpperCase()}_ARM_ZAPPER`,
    );
    const zapper = await ethers.getContractAt("ZapperARM", zapperAddress);
    const armAddress = await parseDeployedAddress(`${arm.toUpperCase()}_ARM`);

    log(`About to deposit ${amount} ${asset} to the ${arm} ARM via the Zapper`);
    const tx = await zapper
      .connect(signer)
      .deposit(armAddress, { value: amountBn });
    await logTxDetails(tx, "zap deposit");
  } else {
    throw new Error(
      `Unsupported asset type: ${asset}. Supported types are WETH, ETH, WS, S.`,
    );
  }
}

async function requestRedeemARM({ arm, amount }) {
  const signer = await getSigner();

  const amountBn = parseUnits(amount.toString());

  const armContract = await resolveArmContract(arm);

  log(
    `About to request a redeem of ${amount} of LP tokens from the ${arm} ARM`,
  );
  const tx = await armContract.connect(signer).requestRedeem(amountBn);
  await logTxDetails(tx, "requestRedeem");
}

async function claimRedeemARM({ arm, id }) {
  const signer = await getSigner();

  const armContract = await resolveArmContract(arm);

  log(`About to claim request with id ${id} from the ${arm} ARM`);
  const tx = await armContract.connect(signer).claimRedeem(id);
  await logTxDetails(tx, "claimRedeem");
}

async function setLiquidityProviderCaps({ accounts, arm, cap }) {
  const signer = await getSigner();

  const capBn = parseUnits(cap.toString());

  const liquidityProviders = accounts.split(",");

  const armContract = await resolveArmContract(arm);
  const capManagerAddress = await armContract.capManager();
  const capManager = await ethers.getContractAt(
    "CapManager",
    capManagerAddress,
  );

  log(
    `About to set deposit cap of ${cap} WETH for liquidity providers ${liquidityProviders} for the ${arm} ARM`,
  );
  const tx = await capManager
    .connect(signer)
    .setLiquidityProviderCaps(liquidityProviders, capBn);
  await logTxDetails(tx, "setLiquidityProviderCaps");
}

async function setTotalAssetsCap({ arm, cap }) {
  const signer = await getSigner();

  const capBn = parseUnits(cap.toString());

  const armContract = await resolveArmContract(arm);
  const capManagerAddress = await armContract.capManager();
  const capManager = await ethers.getContractAt(
    "CapManager",
    capManagerAddress,
  );

  log(`About to set total asset cap of ${cap} for the ${arm} ARM`);
  const tx = await capManager.connect(signer).setTotalAssetsCap(capBn);
  await logTxDetails(tx, "setTotalAssetsCap");
}

module.exports = {
  depositARM,
  requestRedeemARM,
  claimRedeemARM,
  setLiquidityProviderCaps,
  setTotalAssetsCap,
};
