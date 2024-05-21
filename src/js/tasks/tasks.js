const { subtask, task, types } = require("hardhat/config");

const { setAutotaskVars } = require("./autotask");
const {
  autoClaim,
  autoWithdraw,
  claimStEth,
  withdrawStEth,
  withdrawStEthStatus,
} = require("./liquidity");
const { poller, snap } = require("./swapLog");
const { swap } = require("./swap");
const {
  tokenAllowance,
  tokenBalance,
  tokenApprove,
  tokenTransfer,
  tokenTransferFrom,
} = require("./tokens");
const addresses = require("../utils/addresses");
const { getSigner } = require("../utils/signers");

subtask("snap", "Take a snapshot of the OSwap contract")
  .addOptionalParam("pair", "trading pair", "stETH/WETH", types.string)
  .addOptionalParam("amount", "Swap quantity", 100, types.int)
  .addOptionalParam("liq", "Include liquidity", true, types.boolean)
  .addOptionalParam("oneInch", "Include 1Inch prices", true, types.boolean)
  .addOptionalParam("paths", "Include 1Inch swap paths", false, types.boolean)
  .addOptionalParam(
    "start",
    "Starting total OETH and WETH balance",
    704.3184,
    types.float
  )
  // .setAction(snap);
  .setAction(async (taskArgs) => {
    const signer = await getSigner();
    await snap({ ...taskArgs, signer });
  });
task("snap").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("poll", "Poll the 1Inch market prices")
  .addOptionalParam("pair", "trading pair", "stETH/WETH", types.string)
  .addOptionalParam("amount", "Swap quantity", 100, types.int)
  .addOptionalParam("interval", "Minutes between polls", 1, types.int)
  .setAction(poller);
task("poll").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask(
  "swap",
  "Swap from one asset to another. Can only specify the from or to asset"
)
  .addOptionalParam("from", "Symbol of the from asset", undefined, types.string)
  .addOptionalParam("to", "Symbol of the to asset", undefined, types.string)
  .addParam(
    "amount",
    "Swap quantity in either the from or to asset",
    undefined,
    types.float
  )
  .addOptionalParam("pair", "trading pair", "stETH/WETH", types.string)
  .setAction(swap);
task("swap").setAction(async (_, __, runSuper) => {
  return runSuper();
});

// Liquidity management

subtask(
  "autoRequestWithdraw",
  "Calculate the withdraw amount to balance the AMM liquidity and request the withdraw if above a minimum amount from Lido (stETH)"
)
  .addOptionalParam(
    "minAmount",
    "Minimum amount of stETH that can be redeemed",
    50,
    types.float
  )
  .setAction(async (taskArgs) => {
    const signer = await getSigner();
    const stEth = await ethers.getContractAt("IERC20", addresses.mainnet.stETH);
    const weth = await ethers.getContractAt("IWEth", addresses.mainnet.WETH);
    const oSwap = await hre.ethers.getContractAt(
      "LiquidityManagerStEth",
      addresses.mainnet.OEthARM
    );
    const withdrawalQueue = await hre.ethers.getContractAt(
      "IStETHWithdrawal",
      addresses.mainnet.stETHWithdrawalQueue
    );
    await autoWithdraw({
      ...taskArgs,
      signer,
      stEth,
      weth,
      oSwap,
      withdrawalQueue,
    });
  });
task("autoRequestWithdraw").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask(
  "requestWithdraw",
  "Request a specific amount of stETH to withdraw from Lido (stETH)"
)
  .addParam("amount", "stETH withdraw amount", 50, types.float)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();
    const oSwap = await hre.ethers.getContractAt(
      "LiquidityManagerStEth",
      addresses.mainnet.OEthARM
    );
    await withdrawStEth({ ...taskArgs, signer, oSwap });
  });
task("requestWithdraw").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("autoClaimWithdraw", "Claim a requested withdrawal from Lido (stETH)")
  .addOptionalParam("asset", "WETH or ETH", "WETH", types.string)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();
    const oSwap = await hre.ethers.getContractAt(
      "LiquidityManagerStEth",
      addresses.mainnet.OEthARM,
      signer
    );
    const withdrawalQueue = await hre.ethers.getContractAt(
      "IStETHWithdrawal",
      addresses.mainnet.stETHWithdrawalQueue
    );
    await autoClaim({ ...taskArgs, signer, oSwap, withdrawalQueue });
  });
task("autoClaimWithdraw").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("claimWithdraw", "Claim a requested withdrawal from Lido (stETH)")
  .addParam("id", "Request identifier", undefined, types.string)
  .addOptionalParam("asset", "WETH or ETH", "WETH", types.string)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();
    const oSwap = await hre.ethers.getContractAt(
      "LiquidityManagerStEth",
      addresses.mainnet.OEthARM
    );
    await claimStEth({ ...taskArgs, signer, oSwap });
  });
task("claimWithdraw").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("withdrawStatus", "Get the status of a Lido withdrawal request")
  .addParam("id", "Request identifier", undefined, types.string)
  .setAction(withdrawStEthStatus);
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
