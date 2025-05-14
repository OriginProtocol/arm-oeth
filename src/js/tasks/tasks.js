const { subtask, task, types } = require("hardhat/config");

const { mainnet } = require("../utils/addresses");
const {
  parseAddress,
  parseDeployedAddress,
} = require("../utils/addressParser");
const { setAutotaskVars } = require("./autotask");
const { setActionVars } = require("./defender");
const {
  submitLido,
  snapLido,
  swapLido,
  lidoWithdrawStatus,
} = require("./lido");
const { setPrices } = require("./lidoPrices");
const { allocate, collectFees } = require("./admin");
const { requestLidoWithdrawals, claimLidoWithdrawals } = require("./lidoQueue");
const {
  autoRequestWithdraw,
  autoClaimWithdraw,
  requestWithdraw,
  claimWithdraw,
  logLiquidity,
  withdrawRequestStatus,
} = require("./liquidity");
const {
  depositLido,
  requestRedeemLido,
  claimRedeemLido,
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
  allocate: allocateVault,
  capital,
  mint,
  rebase,
  redeem,
  redeemAll,
} = require("./vault");
const { upgradeProxy } = require("./proxy");
const { magpieQuote, magpieTx } = require("../utils/magpie");

subtask(
  "swap",
  "Swap from one asset to another. Can only specify the from or to asset as that will be the exact amount."
)
  .addOptionalParam(
    "from",
    "Symbol of the from asset when swapping from an exact amount",
    "OETH",
    types.string
  )
  .addOptionalParam(
    "to",
    "Symbol of the to asset when swapping to an exact amount",
    undefined,
    types.string
  )
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

subtask(
  "swapLido",
  "Swap from one asset to another. Can only specify the from or to asset as that will be the exact amount."
)
  .addOptionalParam(
    "from",
    "Symbol of the from asset when swapping from an exact amount",
    undefined,
    types.string
  )
  .addOptionalParam(
    "to",
    "Symbol of the to asset when swapping to an exact amount",
    undefined,
    types.string
  )
  .addParam(
    "amount",
    "Swap quantity in either the from or to asset",
    undefined,
    types.float
  )
  .setAction(swapLido);
task("swapLido").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// OETH ARM Liquidity management

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

// Lido tasks

subtask("submitLido", "Convert ETH to Lido's stETH")
  .addParam("amount", "Amount of ETH to convert", undefined, types.float)
  .setAction(submitLido);
task("submitLido").setAction(async (_, __, runSuper) => {
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

task("allocateVault", "Call allocate() on the Vault")
  .addOptionalParam(
    "symbol",
    "Symbol of the OToken. eg OETH or OUSD",
    "OETH",
    types.string
  )
  .setAction(allocateVault);
task("allocateVault").setAction(async (_, __, runSuper) => {
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

// Lido ARM Liquidity Provider Functions

subtask(
  "depositLido",
  "Deposit WETH into the Lido ARM as receive ARM LP tokens"
)
  .addParam(
    "amount",
    "Amount of WETH not scaled to 18 decimals",
    undefined,
    types.float
  )
  .addOptionalParam(
    "asset",
    "Symbol of the asset to deposit. eg ETH or WETH",
    "WETH",
    types.string
  )
  .setAction(depositLido);
task("depositLido").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("requestRedeemLido", "Request redeem from the Lido ARM")
  .addParam(
    "amount",
    "Amount of ARM LP tokens not scaled to 18 decimals",
    undefined,
    types.float
  )
  .setAction(requestRedeemLido);
task("requestRedeemLido").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("claimRedeemLido", "Claim WETH from a previously requested redeem")
  .addParam("id", "Request identifier", undefined, types.float)
  .setAction(claimRedeemLido);
task("claimRedeemLido").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// Capital Management

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

// Lido

subtask("setPrices", "Update Lido ARM's swap prices")
  .addOptionalParam(
    "amount",
    "Swap quantity used for 1Inch pricing",
    100,
    types.int
  )
  .addOptionalParam(
    "buyPrice",
    "The buy price if not using the midPrice.",
    undefined,
    types.float
  )
  .addOptionalParam(
    "midPrice",
    "The middle of the buy and sell prices.",
    undefined,
    types.float
  )
  .addOptionalParam(
    "minSellPrice",
    "The min sell price when pricing off market. eg 1Inch or Curve",
    undefined,
    types.float
  )
  .addOptionalParam(
    "maxSellPrice",
    "The max sell price when pricing off market. eg 1Inch or Curve",
    undefined,
    types.float
  )
  .addOptionalParam(
    "maxBuyPrice",
    "The max buy price when pricing off market. eg 1Inch or Curve",
    undefined,
    types.float
  )
  .addOptionalParam(
    "minBuyPrice",
    "The min buy price when pricing off market. eg 1Inch or Curve",
    undefined,
    types.float
  )
  .addOptionalParam(
    "sellPrice",
    "The sell price if not using the midPrice.",
    undefined,
    types.float
  )
  .addOptionalParam(
    "fee",
    "ARM swap fee in basis points if using mid price",
    1,
    types.float
  )
  .addOptionalParam(
    "offset",
    "Adds extra basis points to the discount if using the mid price. A positive number will lower the prices. A negative number will increase the prices.",
    0,
    types.float
  )
  .addOptionalParam(
    "tolerance",
    "Allowed difference in basis points. eg 1 = 0.0001%",
    0.1,
    types.float
  )
  .addOptionalParam(
    "curve",
    "Set prices off the current Curve mid price.",
    undefined,
    types.boolean
  )
  .addOptionalParam(
    "inch",
    "Set prices off the current 1Inch mid price.",
    undefined,
    types.boolean
  )
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    const lidoArmAddress = await parseDeployedAddress("LIDO_ARM");
    const arm = await ethers.getContractAt("LidoARM", lidoArmAddress);
    await setPrices({ ...taskArgs, signer, arm });
  });
task("setPrices").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask(
  "requestLidoWithdraws",
  "Request withdrawals from the Lido withdrawal queue"
)
  .addOptionalParam(
    "amount",
    "Exact amount of stETH to withdraw. (default: all)",
    undefined,
    types.float
  )
  .addOptionalParam(
    "minAmount",
    "Minimum amount of stETH to withdraw.",
    1,
    types.float
  )
  .addOptionalParam(
    "maxAmount",
    "Maximum amount of stETH to withdraw in each request.",
    300,
    types.float
  )
  .setAction(async (taskArgs) => {
    const signer = await getSigner();
    const steth = await resolveAsset("STETH");

    const lidoArmAddress = await parseDeployedAddress("LIDO_ARM");
    const arm = await ethers.getContractAt("LidoARM", lidoArmAddress);

    await requestLidoWithdrawals({
      ...taskArgs,
      signer,
      steth,
      arm,
    });
  });
task("requestLidoWithdraws").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("claimLidoWithdraws", "Claim requested withdrawals from Lido (stETH)")
  .addOptionalParam(
    "id",
    "Request identifier. (default: all)",
    undefined,
    types.string
  )
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    const lidoArmAddress = await parseDeployedAddress("LIDO_ARM");
    const arm = await ethers.getContractAt("LidoARM", lidoArmAddress);

    const withdrawalQueue = await hre.ethers.getContractAt(
      "IStETHWithdrawal",
      mainnet.lidoWithdrawalQueue
    );

    await claimLidoWithdrawals({
      ...taskArgs,
      signer,
      arm,
      withdrawalQueue,
    });
  });
task("claimLidoWithdraws").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("lidoWithdrawStatus", "Get the status of a Lido withdrawal request")
  .addParam("id", "Request identifier", undefined, types.string)
  .addOptionalParam(
    "block",
    "Block number. (default: latest)",
    undefined,
    types.int
  )
  .setAction(lidoWithdrawStatus);
task("lidoWithdrawStatus").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("collectFees", "Collect the performance fees from an ARM")
  .addOptionalParam(
    "name",
    "The name of the ARM. eg Lido, OETH or Origin",
    "Lido",
    types.string
  )
  .setAction(async ({ name }) => {
    const signer = await getSigner();

    const armAddress = await parseDeployedAddress(`${name.toUpperCase()}_ARM`);
    const arm = await ethers.getContractAt(`${name}ARM`, armAddress);

    await collectFees({ signer, arm });
  });
task("collectFees").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("allocate", "Allocate to/from the active lending market")
  .addOptionalParam(
    "name",
    "The name of the ARM. eg Lido, OETH or Origin",
    "Lido",
    types.string
  )
  .setAction(async ({ name }) => {
    const signer = await getSigner();

    const armAddress = await parseDeployedAddress(`${name.toUpperCase()}_ARM`);
    const arm = await ethers.getContractAt(`${name}ARM`, armAddress);

    await allocate({ signer, arm });
  });
task("allocate").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// ARM Snapshots

subtask("snap", "Take a snapshot of the OETH ARM")
  .addOptionalParam(
    "block",
    "Block number. (default: latest)",
    undefined,
    types.int
  )
  .setAction(logLiquidity);
task("snap").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("snapLido", "Take a snapshot of the Lido ARM")
  .addOptionalParam(
    "block",
    "Block number. (default: latest)",
    undefined,
    types.int
  )
  .addOptionalParam("amount", "Swap quantity", 100, types.int)
  .addOptionalParam("oneInch", "Include 1Inch prices", true, types.boolean)
  .addOptionalParam("curve", "Include Curve prices", true, types.boolean)
  .addOptionalParam("uniswap", "Include Uniswap V3 prices", true, types.boolean)
  .addOptionalParam(
    "queue",
    "Include ARM withdrawal queue data",
    true,
    types.boolean
  )
  .addOptionalParam(
    "lido",
    "Include Lido withdrawal queue data",
    true,
    types.boolean
  )
  .addOptionalParam("user", "Include user data", false, types.boolean)
  .addOptionalParam("cap", "Include cap limit data", false, types.boolean)
  .addOptionalParam("gas", "Include gas costs", false, types.boolean)
  .setAction(snapLido);
task("snapLido").setAction(async (_, __, runSuper) => {
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

// Magpie
subtask("magpieQuote", "Get a quote from Magpie for a swap")
  .addOptionalParam("from", "Token symbol to swap from.", "SILO", types.string)
  .addOptionalParam("to", "Token symbol to swap to.", "WS", types.string)
  .addOptionalParam("amount", "Amount of tokens to sell", 1, types.float)
  .addOptionalParam("slippage", "Max allowed slippage", 0.005, types.float)
  .addOptionalParam(
    "swapper",
    "Account or contract swapping the from tokens",
    "0x531B8D5eD6db72A56cF1238D4cE478E7cB7f2825",
    types.string
  )
  .addOptionalParam(
    "recipient",
    "Where the swapped tokens are sent",
    "0x531B8D5eD6db72A56cF1238D4cE478E7cB7f2825",
    types.string
  )

  .setAction(magpieQuote);
task("magpieQuote").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("magpieTx", "Get a Magpie swap tx based on a previous quote")
  .addParam(
    "id",
    "Identifier returned from a previous quote.",
    undefined,
    types.string
  )

  .setAction(magpieTx);
task("magpieTx").setAction(async (_, __, runSuper) => {
  return runSuper();
});
