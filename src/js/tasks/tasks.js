const { subtask, task, types } = require("hardhat/config");

const { parseAddress } = require("../utils/addressParser");

const { setAutotaskVars } = require("./autotask");
const {
  autoWithdraw,
  requestWithdraw,
  claimWithdraw,
  logLiquidity,
  withdrawRequestStatus,
} = require("./liquidity");
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

subtask("snap", "Take a snapshot of the ARM").setAction(logLiquidity);
task("snap").setAction(async (_, __, runSuper) => {
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
    const oeth = await resolveAsset("OETH");
    const weth = await resolveAsset("WETH");
    const oethArmAddress = await parseAddress("OETH_ARM");
    const oethARM = await ethers.getContractAt("OEthARM", oethArmAddress);
    await autoWithdraw({
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
  "requestWithdraw",
  "Request a specific amount of stETH to withdraw from Lido (stETH)"
)
  .addParam("amount", "OETH withdraw amount", 50, types.float)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    const oethArmAddress = await parseAddress("OETH_ARM");
    const oethARM = await ethers.getContractAt("OEthARM", oethArmAddress);

    await requestWithdraw({ ...taskArgs, signer, oethARM });
  });
task("requestWithdraw").setAction(async (_, __, runSuper) => {
  return runSuper();
});

subtask("claimWithdraw", "Claim a requested withdrawal from Lido (stETH)")
  .addParam("id", "Request identifier", undefined, types.string)
  .setAction(async (taskArgs) => {
    const signer = await getSigner();

    const oethArmAddress = await parseAddress("OETH_ARM");
    const oethARM = await ethers.getContractAt("OEthARM", oethArmAddress);

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
    const oethARM = await ethers.getContractAt("OEthARM", oethArmAddress);

    await withdrawRequestStatus({ ...taskArgs, signer, oethARM });
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
