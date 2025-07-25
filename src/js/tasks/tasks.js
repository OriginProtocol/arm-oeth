const { parseUnits } = require("ethers");
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
const {
  collectRewards,
  harvestRewards,
  setHarvester,
} = require("./sonicHarvest");
const { requestLidoWithdrawals, claimLidoWithdrawals } = require("./lidoQueue");
const {
  autoRequestWithdraw,
  autoClaimWithdraw,
  requestWithdraw,
  claimWithdraw,
  logLiquidity,
  withdrawRequestStatus,
} = require("./liquidity");
const { logArmPrices } = require("./markets");
const {
  depositARM,
  requestRedeemARM,
  claimRedeemARM,
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
const { flyTradeQuote, flyTradeTx } = require("../utils/magpie");
const { setOperator } = require("./governance");

const { setOSSiloPrice } = require("./osSiloPrice");

subtask(
  "swap",
  "Swap from one asset to another. Can only specify the from or to asset as that will be the exact amount."
)
  .addParam(
    "arm",
    "Name of the ARM. eg Lido, Origin or Oeth",
    "Lido",
    types.string
  )
  .addParam(
    "amount",
    "Swap quantity in either the from or to asset",
    undefined,
    types.float
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
    "arm",
    "The name of the ARM. eg Oeth or Origin",
    "Oeth",
    types.string
  )
  .addOptionalParam(
    "minAmount",
    "Minimum amount of OETH that will be withdrawn",
    2,
    types.float
  )
  .setAction(async (taskArgs) => {
    const arm = taskArgs.arm;
    const signer = await getSigner();
    const assetSymbol = arm === "OETH" ? "OETH" : "OS";
    const asset = await resolveAsset(assetSymbol);

    const armAddress = await parseAddress(`${arm.toUpperCase()}_ARM`);
    const armContract = await ethers.getContractAt(`${arm}ARM`, armAddress);

    await autoRequestWithdraw({
      ...taskArgs,
      signer,
      asset,
      arm: armContract,
    });
  });
task("autoRequestWithdraw").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("autoClaimWithdraw", "Claim withdrawal requests from the OETH Vault")
  .addOptionalParam(
    "arm",
    "The name of the ARM. eg Oeth or Origin",
    "Oeth",
    types.string
  )
  .setAction(async (taskArgs) => {
    const arm = taskArgs.arm;
    const signer = await getSigner();
    const liquiditySymbol = arm === "Oeth" ? "WETH" : "WS";
    const liquidityAsset = await resolveAsset(liquiditySymbol);

    const armAddress = await parseAddress(`${arm.toUpperCase()}_ARM`);
    const armContract = await ethers.getContractAt(`${arm}ARM`, armAddress);

    const vaultName = arm === "Oeth" ? "OETH" : "OS";
    const vaultAddress = await parseAddress(`${vaultName}_VAULT`);
    const vault = await ethers.getContractAt("IOriginVault", vaultAddress);

    await autoClaimWithdraw({
      ...taskArgs,
      signer,
      liquidityAsset,
      arm: armContract,
      vault,
    });
  });
task("autoClaimWithdraw").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask(
  "requestWithdraw",
  "Request a specific amount of oTokens to withdraw from the Vault"
)
  .addOptionalParam(
    "arm",
    "The name of the ARM. eg Oeth or Origin",
    "Oeth",
    types.string
  )
  .addParam("amount", "OETH withdraw amount", 50, types.float)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    const armAddress = await parseAddress(`${taskArgs.arm.toUpperCase()}_ARM`);
    const armContract = await ethers.getContractAt(
      `${taskArgs.arm}ARM`,
      armAddress
    );

    await requestWithdraw({
      ...taskArgs,
      signer,
      armName: taskArgs.arm,
      arm: armContract,
    });
  });
task("requestWithdraw").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("claimWithdraw", "Claim a requested oToken withdrawal from the Vault")
  .addOptionalParam(
    "arm",
    "The name of the ARM. eg Oeth or Origin",
    "Oeth",
    types.string
  )
  .addParam("id", "Request identifier", undefined, types.string)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    const armAddress = await parseAddress(`${taskArgs.arm.toUpperCase()}_ARM`);
    const armContract = await ethers.getContractAt(
      `${taskArgs.arm}ARM`,
      armAddress
    );

    await claimWithdraw({
      ...taskArgs,
      signer,
      armName: taskArgs.arm,
      arm: armContract,
    });
  });
task("claimWithdraw").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("withdrawStatus", "Get the status of a OETH withdrawal request")
  .addOptionalParam(
    "arm",
    "The name of the ARM. eg Oeth or Origin",
    "Oeth",
    types.string
  )
  .addParam("id", "Request number", undefined, types.string)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    const armAddress = await parseAddress(`${taskArgs.arm.toUpperCase()}_ARM`);
    const armContract = await ethers.getContractAt(
      `${taskArgs.arm}ARM`,
      armAddress
    );
    const vaultName = taskArgs.arm === "Oeth" ? "OETH_VAULT" : "OS_VAULT";
    const vaultAddress = await parseAddress(vaultName);
    const vault = await ethers.getContractAt("IOriginVault", vaultAddress);

    await withdrawRequestStatus({
      ...taskArgs,
      signer,
      arm: armContract,
      vault,
    });
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

subtask("depositARM", "Deposit to an ARM and receive ARM LP tokens")
  .addParam("arm", "Name of the ARM. eg Lido or Origin", "Lido", types.string)
  .addParam(
    "amount",
    "Amount of to deposit not scaled to 18 decimals",
    undefined,
    types.float
  )
  .addOptionalParam(
    "asset",
    "Symbol of the asset to deposit. eg ETH, WETH, S or WS",
    "WETH",
    types.string
  )
  .setAction(depositARM);
task("depositARM").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("requestRedeemARM", "Request redeem from an ARM")
  .addParam("arm", "Name of the ARM. eg Lido or Origin", "Lido", types.string)
  .addParam(
    "amount",
    "Amount of ARM LP tokens not scaled to 18 decimals",
    undefined,
    types.float
  )
  .setAction(requestRedeemARM);
task("requestRedeemARM").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("claimRedeemARM", "Claim from a previously requested ARM redeem")
  .addParam("arm", "Name of the ARM. eg Lido or Origin", "Lido", types.string)
  .addParam("id", "Request identifier", undefined, types.float)
  .setAction(claimRedeemARM);
task("claimRedeemARM").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// Capital Management

subtask("setLiquidityProviderCaps", "Set deposit cap for liquidity providers")
  .addParam("arm", "Name of the ARM. eg Lido or Origin", "Lido", types.string)
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
  .addParam("arm", "Name of the ARM. eg Lido or Origin", "Lido", types.string)
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
    "arm",
    "The name of the ARM. eg Lido or Origin",
    "Lido",
    types.string
  )
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

    const armAddress = await parseDeployedAddress(
      `${taskArgs.arm.toUpperCase()}_ARM`
    );
    const armContract = await ethers.getContractAt("AbstractARM", armAddress);

    await setPrices({ ...taskArgs, signer, arm: armContract });
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
    "The name of the ARM. eg Lido or Origin",
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

subtask("collectRewards", "Collect rewards")
  .addOptionalParam(
    "arm",
    "The name of the ARM to collect rewards for. eg Lido or Origin",
    "Origin",
    types.string
  )
  .setAction(async () => {
    const signer = await getSigner();

    const siloMarketAddress = await parseDeployedAddress(
      "SILO_VARLAMORE_S_MARKET"
    );
    const harvesterAddress = await parseDeployedAddress("HARVESTER");
    const harvester = await ethers.getContractAt(
      "SonicHarvester",
      harvesterAddress
    );

    await collectRewards({
      signer,
      harvester,
      strategies: [siloMarketAddress],
    });
  });
task("collectRewards").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("harvestRewards", "harvest rewards")
  .addOptionalParam(
    "name",
    "The name of the ARM. eg Lido or Origin",
    "Origin",
    types.string
  )
  .addOptionalParam(
    "token",
    "The symbol of the reward token. eg Silo, beS, OS",
    "Silo",
    types.string
  )
  .setAction(async ({ token }) => {
    const signer = await getSigner();

    const harvesterAddress = await parseDeployedAddress("HARVESTER");
    const harvester = await ethers.getContractAt(
      "SonicHarvester",
      harvesterAddress
    );

    await harvestRewards({ signer, harvester, symbol: token });
  });
task("harvestRewards").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("setHarvester", "Set the harvester on a lending market")
  .addOptionalParam(
    "name",
    "The name of the ARM. eg Lido or Origin",
    "Origin",
    types.string
  )
  .setAction(async () => {
    const signer = await getSigner();

    const harvester = await parseDeployedAddress("HARVESTER");

    const siloMarketAddress = await parseDeployedAddress(
      "SILO_VARLAMORE_S_MARKET"
    );
    const siloMarket = await ethers.getContractAt(
      "SiloMarket",
      siloMarketAddress
    );

    await setHarvester({ signer, siloMarket, harvester });
  });
task("setHarvester").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("allocate", "Allocate to/from the active lending market")
  .addOptionalParam(
    "arm",
    "The name of the ARM. eg Lido, OETH or Origin",
    "Origin",
    types.string
  )
  .addOptionalParam(
    "threshold",
    "The liquidity delta before threshold before allocate is called",
    undefined,
    types.float
  )
  .setAction(async ({ arm, threshold }) => {
    const signer = await getSigner();

    const armAddress = await parseDeployedAddress(`${arm.toUpperCase()}_ARM`);
    const armContract = await ethers.getContractAt(`${arm}ARM`, armAddress);

    await allocate({ signer, arm: armContract, threshold });
  });
task("allocate").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// Governance

subtask("setOperator", "Set the operator of a contract")
  .addParam("contract", "Name of a proxy contract", undefined, types.string)
  .addParam("operator", "Address of the Operator", undefined, types.string)
  .setAction(async ({ contract: contractName, operator }) => {
    const signer = await getSigner();

    const contractAddress = await parseDeployedAddress(contractName);
    const contract = await ethers.getContractAt(
      "OwnableOperable",
      contractAddress
    );

    await setOperator({ signer, contract, operator });
  });
task("setOperator").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// ARM Snapshots

subtask("snap", "Take a snapshot of the an ARM")
  .addOptionalParam(
    "arm",
    "The name of the ARM. eg Lido, OETH or Origin",
    "Lido",
    types.string
  )
  .addOptionalParam(
    "block",
    "Block number. (default: latest)",
    undefined,
    types.int
  )
  .setAction(async (taskArgs) => {
    await logLiquidity(taskArgs);

    if (taskArgs.arm.toUpperCase() === "OETH") return;

    const armAddress = await parseAddress(`${taskArgs.arm.toUpperCase()}_ARM`);
    const armContract = await ethers.getContractAt(
      `${taskArgs.arm}ARM`,
      armAddress
    );
    await logArmPrices(taskArgs, armContract);
  });
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

// FlyTrade
subtask("flyTradeQuote", "Get a Fly quote for a swap")
  .addOptionalParam("from", "Token symbol to swap from.", "SILO", types.string)
  .addOptionalParam("to", "Token symbol to swap to.", "WS", types.string)
  .addOptionalParam("amount", "Amount of tokens to sell", 1, types.float)
  .addOptionalParam("slippage", "Max allowed slippage", 0.005, types.float)
  .addOptionalParam(
    "swapper",
    "Account or contract swapping the from tokens",
    "0x08876C0F5a80c1a43A6396b13A881A26F4b6Adfe",
    types.string
  )
  .addOptionalParam(
    "recipient",
    "Where the swapped tokens are sent",
    "0x2F872623d1E1Af5835b08b0E49aAd2d81d649D30",
    types.string
  )
  .setAction(async (taskArgs) => {
    const amount = parseUnits(taskArgs.amount.toString(), 18);

    await flyTradeQuote({ ...taskArgs, amount });
  });
task("flyTradeQuote").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("flyTradeTx", "Get a Fly swap tx based on a previous quote")
  .addParam(
    "id",
    "Identifier returned from a previous quote.",
    undefined,
    types.string
  )
  .setAction(async (taskArgs) => {
    await flyTradeTx(taskArgs);
  });
task("flyTradeTx").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// OS Silo Prices
subtask("setOSSiloPrice", "Update Origin ARM's swap prices based on lending APY and market pricing")
  .addOptionalParam("execute", "Execute the transaction", false, types.boolean)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    const armAddress = "0x2F872623d1E1Af5835b08b0E49aAd2d81d649D30";
    const arm = await hre.ethers.getContractAt([
      "function traderate0() external view returns (uint256)",
      "function traderate1() external view returns (uint256)",
      "function activeMarket() external view returns (address)",
    ], armAddress, signer);

    const activeMarket = await arm.activeMarket();
    if (activeMarket === ethers.ZeroAddress) {
      log("No active lending market found, using default APY of 0%");
      return 0n;
    }

    // Get the SiloMarketWrapper contract
    const siloMarketWrapper = await hre.ethers.getContractAt([
      "function market() external view returns (address)",
    ], activeMarket, signer);

    await setOSSiloPrice({ tolerance: taskArgs.tolerance, signer, arm, siloMarketWrapper });
  });
task("setOSSiloPrice").setAction(async (_, __, runSuper) => {
  return runSuper();
});
