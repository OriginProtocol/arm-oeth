const { subtask, task, types } = require("hardhat/config");
const { formatUnits, parseUnits } = require("ethers");

const {
  parseAddress,
  parseDeployedAddress,
} = require("../utils/addressParser");
const { setAutotaskVars } = require("./autotask");
const { setActionVars } = require("./defender");
const {
  autoRequestWithdraw,
  autoClaimWithdraw,
  requestWithdraw,
  claimWithdraw,
  logLiquidity,
  withdrawRequestStatus,
} = require("./liquidity");
const {
  lpDeposit,
  setLiquidityProviderCaps,
  setTotalAssetsCap,
} = require("./liquidityProvider");
const { swap } = require("./swap");
const {
  tokenAllowance,
  tokenBalance,
  tokenApprove,
  tokenTransfer,
  tokenTransferFrom,
} = require("./tokens");
const { getSigner } = require("../utils/signers");
const { resolveAsset } = require("../utils/assets");
const { depositWETH, withdrawWETH } = require("./weth");
const {
  addWithdrawalQueueLiquidity,
  allocate,
  capital,
  mint,
  rebase,
  redeem,
  redeemAll,
} = require("./vault");
const { upgradeProxy } = require("./proxy");

subtask("snap", "Take a snapshot of the ARM").setAction(logLiquidity);
task("snap").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask(
  "swap",
  "Swap from one asset to another. Can only specify the from or to asset"
)
  .addOptionalParam("from", "Symbol of the from asset", "OETH", types.string)
  .addOptionalParam("to", "Symbol of the to asset", undefined, types.string)
  .addParam(
    "amount",
    "Swap quantity in either the from or to asset",
    undefined,
    types.float
  )
  .setAction(swap);
task("swap").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// Liquidity management

subtask("autoRequestWithdraw", "Request withdrawal of WETH from the OETH Vault")
  .addOptionalParam(
    "minAmount",
    "Minimum amount of OETH that will be withdrawn",
    2,
    types.float
  )
  .setAction(async (taskArgs) => {
    const signer = await getSigner();
    const oeth = await resolveAsset("OETH");
    const weth = await resolveAsset("WETH");
    const oethArmAddress = await parseAddress("OETH_ARM");
    const oethARM = await ethers.getContractAt("OethARM", oethArmAddress);
    await autoRequestWithdraw({
      ...taskArgs,
      signer,
      oeth,
      weth,
      oethARM,
    });
  });
task("autoRequestWithdraw").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask(
  "autoClaimWithdraw",
  "Claim withdrawal requests from the OETH Vault"
).setAction(async (taskArgs) => {
  const signer = await getSigner();
  const weth = await resolveAsset("WETH");
  const oethArmAddress = await parseAddress("OETH_ARM");
  const oethARM = await ethers.getContractAt("OethARM", oethArmAddress);
  const vaultAddress = await parseAddress("OETH_VAULT");
  const vault = await ethers.getContractAt("IOETHVault", vaultAddress);

  await autoClaimWithdraw({
    ...taskArgs,
    signer,
    weth,
    oethARM,
    vault,
  });
});
task("autoClaimWithdraw").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask(
  "requestWithdraw",
  "Request a specific amount of OETH to withdraw from the OETH Vault"
)
  .addParam("amount", "OETH withdraw amount", 50, types.float)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    const oethArmAddress = await parseAddress("OETH_ARM");
    const oethARM = await ethers.getContractAt("OethARM", oethArmAddress);

    await requestWithdraw({ ...taskArgs, signer, oethARM });
  });
task("requestWithdraw").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("claimWithdraw", "Claim a requested withdrawal from the OETH Vault")
  .addParam("id", "Request identifier", undefined, types.string)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    const oethArmAddress = await parseAddress("OETH_ARM");
    const oethARM = await ethers.getContractAt("OethARM", oethArmAddress);

    await claimWithdraw({ ...taskArgs, signer, oethARM });
  });
task("claimWithdraw").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("withdrawStatus", "Get the status of a OETH withdrawal request")
  .addParam("id", "Request number", undefined, types.string)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    const oethArmAddress = await parseAddress("OETH_ARM");
    const oethARM = await ethers.getContractAt("OethARM", oethArmAddress);
    const vaultAddress = await parseAddress("OETH_VAULT");
    const vault = await ethers.getContractAt("IOETHVault", vaultAddress);

    await withdrawRequestStatus({ ...taskArgs, signer, oethARM, vault });
  });
task("withdrawStatus").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// Defender
subtask(
  "setAutotaskVars",
  "Set environment variables on Defender Autotasks. eg DEBUG=origin*"
)
  .addOptionalParam(
    "id",
    "Identifier of the Defender Autotask",
    "ffcfc580-7b0a-42ed-a4f2-3f0a3add9779",
    types.string
  )
  .setAction(setAutotaskVars);
task("setAutotaskVars").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// Token tasks.
subtask("allowance", "Get the token allowance an owner has given to a spender")
  .addParam(
    "symbol",
    "Symbol of the token. eg OETH, WETH, USDT or OGV",
    undefined,
    types.string
  )
  .addParam(
    "spender",
    "The address of the account or contract that can spend the tokens"
  )
  .addOptionalParam(
    "owner",
    "The address of the account or contract allowing the spending. Default to the signer"
  )
  .addOptionalParam(
    "block",
    "Block number. (default: latest)",
    undefined,
    types.int
  )
  .setAction(tokenAllowance);
task("allowance").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("balance", "Get the token balance of an account or contract")
  .addParam(
    "symbol",
    "Symbol of the token. eg OETH, WETH, USDT or OGV",
    undefined,
    types.string
  )
  .addOptionalParam(
    "account",
    "The address of the account or contract. Default to the signer"
  )
  .addOptionalParam(
    "block",
    "Block number. (default: latest)",
    undefined,
    types.int
  )
  .setAction(tokenBalance);
task("balance").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("approve", "Approve an account or contract to spend tokens")
  .addParam(
    "symbol",
    "Symbol of the token. eg OETH, WETH, USDT or OGV",
    undefined,
    types.string
  )
  .addParam(
    "amount",
    "Amount of tokens that can be spent",
    undefined,
    types.float
  )
  .addParam(
    "spender",
    "Address of the account or contract that can spend the tokens",
    undefined,
    types.string
  )
  .setAction(tokenApprove);
task("approve").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("transfer", "Transfer tokens to an account or contract")
  .addParam(
    "symbol",
    "Symbol of the token. eg OETH, WETH, USDT or OGV",
    undefined,
    types.string
  )
  .addParam("amount", "Amount of tokens to transfer", undefined, types.float)
  .addParam("to", "Destination address", undefined, types.string)
  .setAction(tokenTransfer);
task("transfer").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("transferFrom", "Transfer tokens from an account or contract")
  .addParam(
    "symbol",
    "Symbol of the token. eg OETH, WETH, USDT or OGV",
    undefined,
    types.string
  )
  .addParam("amount", "Amount of tokens to transfer", undefined, types.float)
  .addParam("from", "Source address", undefined, types.string)
  .addOptionalParam(
    "to",
    "Destination address. Default to signer",
    undefined,
    types.string
  )
  .setAction(tokenTransferFrom);
task("transferFrom").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// WETH tasks
subtask("depositWETH", "Deposit ETH into WETH")
  .addParam("amount", "Amount of ETH to deposit", undefined, types.float)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    const wethAddress = await parseAddress("WETH");
    const weth = await ethers.getContractAt("IWETH", wethAddress);

    await depositWETH({ ...taskArgs, weth, signer });
  });
task("depositWETH").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("withdrawWETH", "Withdraw ETH from WETH")
  .addParam("amount", "Amount of ETH to withdraw", undefined, types.float)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    const wethAddress = await parseAddress("WETH");
    const weth = await ethers.getContractAt("IWETH", wethAddress);

    await withdrawWETH({ ...taskArgs, weth, signer });
  });
task("withdrawWETH").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// Vault tasks.

task(
  "queueLiquidity",
  "Call addWithdrawalQueueLiquidity() on the Vault to add WETH to the withdrawal queue"
).setAction(addWithdrawalQueueLiquidity);
task("queueLiquidity").setAction(async (_, __, runSuper) => {
  return runSuper();
});

task("allocate", "Call allocate() on the Vault")
  .addOptionalParam(
    "symbol",
    "Symbol of the OToken. eg OETH or OUSD",
    "OETH",
    types.string
  )
  .setAction(allocate);
task("allocate").setAction(async (_, __, runSuper) => {
  return runSuper();
});

task("capital", "Set the Vault's pauseCapital flag")
  .addOptionalParam(
    "symbol",
    "Symbol of the OToken. eg OETH or OUSD",
    "OETH",
    types.string
  )
  .addParam(
    "pause",
    "Whether to pause or unpause the capital allocation",
    "true",
    types.boolean
  )
  .setAction(capital);
task("capital").setAction(async (_, __, runSuper) => {
  return runSuper();
});

task("rebase", "Call rebase() on the Vault")
  .addOptionalParam(
    "symbol",
    "Symbol of the OToken. eg OETH or OUSD",
    "OETH",
    types.string
  )
  .setAction(rebase);
task("rebase").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("mint", "Mint OTokens from the Vault using collateral assets")
  .addParam(
    "asset",
    "Symbol of the collateral asset to deposit. eg WETH, USDT, DAI",
    "WETH",
    types.string
  )
  .addParam(
    "amount",
    "Amount of collateral assets to deposit",
    undefined,
    types.float
  )
  .addOptionalParam("min", "Minimum amount of OETH to mint", 0, types.float)
  .addOptionalParam(
    "approve",
    "Approve the asset to the OETH Vault before the mint",
    true,
    types.boolean
  )
  .setAction(mint);
task("mint").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("redeem", "Redeem OTokens for collateral assets from the Vault")
  .addParam("amount", "Amount of OTokens to burn", undefined, types.float)
  .addOptionalParam(
    "symbol",
    "Symbol of the OToken. eg OETH or OUSD",
    "OETH",
    types.string
  )
  .addOptionalParam(
    "min",
    "Minimum amount of collateral to receive",
    0,
    types.float
  )
  .setAction(redeem);
task("redeem").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("redeemAll", "Redeem all OTokens for collateral assets from the Vault")
  .addOptionalParam(
    "symbol",
    "Symbol of the OToken. eg OETH or OUSD",
    "OETH",
    types.string
  )
  .addOptionalParam(
    "min",
    "Minimum amount of collateral to receive",
    0,
    types.float
  )
  .setAction(redeemAll);
task("redeemAll").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// ARM Liquidity Provider Functions

subtask("lpDeposit", "Set total assets cap")
  .addParam(
    "amount",
    "Amount of WETH not scaled to 18 decimals",
    undefined,
    types.float
  )
  .setAction(lpDeposit);
task("lpDeposit").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("setLiquidityProviderCaps", "Set deposit cap for liquidity providers")
  .addParam(
    "cap",
    "Amount of WETH not scaled to 18 decimals",
    undefined,
    types.float
  )
  .addParam(
    "accounts",
    "Comma separated list of addresses",
    undefined,
    types.string
  )
  .setAction(setLiquidityProviderCaps);
task("setLiquidityProviderCaps").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("setTotalAssetsCap", "Set total assets cap")
  .addParam(
    "cap",
    "Amount of WETH not scaled to 18 decimals",
    undefined,
    types.float
  )
  .setAction(setTotalAssetsCap);
task("setTotalAssetsCap").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// Proxies

subtask("upgradeProxy", "Upgrade a proxy contract to a new implementation")
  .addParam("proxy", "Address of the proxy contract", undefined, types.string)
  .addParam(
    "impl",
    "Address of the implementation contract",
    undefined,
    types.string
  )
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    await upgradeProxy({ ...taskArgs, signer });
  });
task("upgradeProxy").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// Defender
subtask(
  "setActionVars",
  "Set environment variables on a Defender Actions. eg DEBUG=origin*"
)
  .addParam("id", "Identifier of the Defender Actions", undefined, types.string)
  .setAction(setActionVars);
task("setActionVars").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask(
  "postDeploy",
  "Used for Testnets after running the Lido deploy script"
).setAction(async () => {
  const signer = await getSigner();

  const wethAddress = await parseAddress("WETH");
  const stethAddress = await parseAddress("STETH");
  const lidoArmAddress = await parseDeployedAddress("LIDO_ARM");
  const lidoArmImpl = parseDeployedAddress("LIDO_ARM_IMPL");
  const relayerAddress = await parseAddress("ARM_RELAYER");
  const liquidityProviderController = await parseDeployedAddress(
    "LIDO_ARM_LPC"
  );
  const feeCollector = await parseAddress("ARM_BUYBACK");

  const weth = await ethers.getContractAt("IWETH", wethAddress);
  const steth = await ethers.getContractAt("IWETH", stethAddress);
  const legacyAMM = await ethers.getContractAt("LegacyAMM", lidoArmAddress);
  const lidoARM = await ethers.getContractAt("LidoARM", lidoArmAddress);
  const lidoProxy = await ethers.getContractAt("Proxy", lidoArmAddress);

  const wethBalance = await weth.balanceOf(lidoArmAddress);
  console.log(
    `Amount to transfer ${formatUnits(wethBalance)} WETH out of the LidoARM`
  );
  await legacyAMM
    .connect(signer)
    .transferToken(wethAddress, await signer.getAddress(), wethBalance);

  const stethBalance = await steth.balanceOf(lidoArmAddress);
  console.log(
    `Amount to transfer ${formatUnits(stethBalance)} stETH out of the LidoARM`
  );
  await legacyAMM
    .connect(signer)
    .transferToken(stethAddress, await signer.getAddress(), stethBalance);

  console.log(`Amount to approve the Lido ARM`);
  await weth.connect(signer).approve(lidoArmAddress, "1000000000000");

  const initData = lidoARM.interface.encodeFunctionData(
    "initialize(string,string,address,uint256,address,address)",
    [
      "Lido ARM",
      "ARM-ST",
      relayerAddress,
      1500, // 15% performance fee
      feeCollector,
      liquidityProviderController,
    ]
  );

  console.log(`Amount to upgradeToAndCall the Lido ARM`);
  await lidoProxy.connect(signer).upgradeToAndCall(lidoArmImpl, initData);

  console.log(`Amount to setPrices on the Lido ARM`);
  await lidoARM
    .connect(signer)
    .setPrices(parseUnits("9994", 32), parseUnits("9999", 32));

  console.log(`Amount to setOwner on the Lido ARM`);
  await lidoProxy.connect(signer).setOwner(await parseAddress("GOV_MULTISIG"));
});
task("postDeploy").setAction(async (_, __, runSuper) => {
  return runSuper();
});
