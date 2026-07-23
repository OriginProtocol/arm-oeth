const { parseUnits } = require("ethers");

const {
  setLiquidityProviderCaps: setLiquidityProviderCapsCore,
  setTotalAssetsCap: setTotalAssetsCapCore,
} = require("./admin");
const { getSigner } = require("../utils/signers");
const { liquiditySymbol, normalizeArmName } = require("../utils/arm");
const {
  parseDeployedAddress,
  resolveArmContract,
} = require("../utils/addressParser");
const { logTxDetails } = require("../utils/txLogger");

const log = require("../utils/logger")("task:lpCap");

const resolveLiquidityAssetContext = async (armContract) => {
  const liquidityAddress = await armContract.liquidityAsset();
  const liquidityAsset = await ethers.getContractAt(
    "IERC20Metadata",
    liquidityAddress,
  );

  const [symbol, decimals] = await Promise.all([
    liquidityAsset.symbol(),
    liquidityAsset.decimals(),
  ]);

  return {
    address: liquidityAddress,
    decimals: Number(decimals),
    symbol: symbol.toUpperCase(),
  };
};

async function depositARM({ amount, asset, arm, execute = true }) {
  const signer = await getSigner();
  const armName = normalizeArmName(arm);
  const armContract = await resolveArmContract(arm);
  const liquidityAsset = await resolveLiquidityAssetContext(armContract);
  const expectedAsset = liquiditySymbol(armName);
  const assetSymbol = (asset ?? expectedAsset).toUpperCase();

  if (assetSymbol === liquidityAsset.symbol) {
    const amountBn = parseUnits(amount.toString(), liquidityAsset.decimals);
    log(
      `About to deposit ${amount} ${liquidityAsset.symbol} to the ${armName} ARM`,
    );
    if (!execute) return;
    const tx = await armContract.connect(signer).deposit(amountBn);
    await logTxDetails(tx, "deposit");
  } else if (assetSymbol == "ETH") {
    const amountBn = parseUnits(amount.toString(), 18);
    const zapperAddress = await parseDeployedAddress("ARM_ZAPPER");
    const zapper = await ethers.getContractAt("ZapperARM", zapperAddress);

    const armAddress = await armContract.getAddress();

    log(`About to deposit ${amount} ETH to ARM ${armAddress} via the Zapper`);
    if (!execute) return;
    const tx = await zapper
      .connect(signer)
      .deposit(armAddress, { value: amountBn });
    await logTxDetails(tx, "zap deposit");
  } else if (assetSymbol == "S") {
    const amountBn = parseUnits(amount.toString(), 18);
    const zapperAddress = await parseDeployedAddress(
      `${armName.toUpperCase()}_ARM_ZAPPER`,
    );
    const zapper = await ethers.getContractAt("ZapperARM", zapperAddress);
    const armAddress = await armContract.getAddress();

    log(
      `About to deposit ${amount} ${assetSymbol} to the ${armName} ARM via the Zapper`,
    );
    if (!execute) return;
    const tx = await zapper
      .connect(signer)
      .deposit(armAddress, { value: amountBn });
    await logTxDetails(tx, "zap deposit");
  } else {
    throw new Error(
      `Unsupported asset type: ${assetSymbol}. ${armName} ARM deposits use ${liquidityAsset.symbol}. Native deposits are supported for ETH and S zappers.`,
    );
  }
}

async function requestRedeemARM({ arm, amount, execute = true }) {
  const signer = await getSigner();

  const amountBn = parseUnits(amount.toString());

  const armContract = await resolveArmContract(arm);

  log(
    `About to request a redeem of ${amount} of LP tokens from the ${arm} ARM`,
  );
  if (!execute) return;
  const tx = await armContract.connect(signer).requestRedeem(amountBn);
  await logTxDetails(tx, "requestRedeem");
}

async function claimRedeemARM({ arm, id, execute = true }) {
  const signer = await getSigner();

  const armContract = await resolveArmContract(arm);

  log(`About to claim request with id ${id} from the ${arm} ARM`);
  if (!execute) return;
  const tx = await armContract.connect(signer).claimRedeem(id);
  await logTxDetails(tx, "claimRedeem");
}

async function setLiquidityProviderCaps({ accounts, arm, cap }) {
  const signer = await getSigner();
  const armContract = await resolveArmContract(arm);
  const liquidityAsset = await resolveLiquidityAssetContext(armContract);

  await setLiquidityProviderCapsCore({
    accounts,
    arm: armContract,
    armName: arm,
    cap,
    decimals: liquidityAsset.decimals,
    signer,
  });
}

async function setTotalAssetsCap({ arm, cap }) {
  const signer = await getSigner();
  const armContract = await resolveArmContract(arm);
  const liquidityAsset = await resolveLiquidityAssetContext(armContract);

  await setTotalAssetsCapCore({
    arm: armContract,
    armName: arm,
    cap,
    decimals: liquidityAsset.decimals,
    signer,
  });
}

module.exports = {
  depositARM,
  requestRedeemARM,
  claimRedeemARM,
  setLiquidityProviderCaps,
  setTotalAssetsCap,
};
