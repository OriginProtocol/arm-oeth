const { execSync } = require("child_process");
const { ethers } = require("ethers");
const { allocate, collectFees, setARMBuffer } = require("./admin");

// Redirect console.log to stderr so stdout stays clean for ABI-encoded output
console.log = console.error;

/**
 * Fetch the ABI for a proxy contract using cast.
 * Resolves the implementation address first, then fetches the ABI via etherscan.
 */
function fetchAbi(address, rpcUrl) {
  // Check if the contract is a proxy and resolve the implementation if so
  const implAddress = execSync(
    `cast implementation ${address} --rpc-url ${rpcUrl}`,
    { encoding: "utf-8" },
  ).trim();

  const targetAddress =
    implAddress !== ethers.ZeroAddress ? implAddress : address;

  // Fetch the ABI from etherscan as a Solidity interface
  const iface = execSync(`cast interface ${targetAddress} --chain mainnet`, {
    encoding: "utf-8",
  });

  // Extract function signatures from the Solidity interface
  // Lines like: "    function allocate() external returns (int256, int256);"
  const sigs = iface
    .split("\n")
    .filter((line) => line.trim().startsWith("function "))
    .map((line) => line.trim().replace(";", ""));

  return sigs;
}

function encodeResult(result) {
  const coder = ethers.AbiCoder.defaultAbiCoder();
  if (!result || !result.shouldExecute) {
    return coder.encode(
      ["bool", "address", "bytes"],
      [false, ethers.ZeroAddress, "0x"],
    );
  }
  return coder.encode(
    ["bool", "address", "bytes"],
    [true, result.target, result.calldata],
  );
}

function parseArgs(argv) {
  const args = {};
  // First positional arg is action, second is ARM address
  const positional = [];
  for (let i = 2; i < argv.length; i++) {
    if (argv[i].startsWith("--")) {
      const key = argv[i].slice(2);
      args[key] = argv[++i];
    } else {
      positional.push(argv[i]);
    }
  }
  args.action = positional[0];
  args.arm = positional[1];
  return args;
}

async function main() {
  const args = parseArgs(process.argv);

  if (!args.action || !args.arm) {
    console.error(
      "Usage: node runner.js <action> <armAddress> [--threshold N] [--maxGasPrice N] [--armContractVersion v1|v2]",
    );
    process.exit(1);
  }

  const rpcUrl = process.env.PROVIDER_URL;
  if (!rpcUrl) {
    console.error("PROVIDER_URL environment variable is required");
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const armAbi = fetchAbi(args.arm, rpcUrl);
  const arm = new ethers.Contract(args.arm, armAbi, provider);

  let result;
  switch (args.action) {
    case "allocate":
      result = await allocate({
        arm,
        provider,
        threshold: args.threshold ? Number(args.threshold) : undefined,
        maxGasPrice: args.maxGasPrice ? Number(args.maxGasPrice) : undefined,
        armContractVersion: args.armContractVersion || "v2",
      });
      break;
    case "collectFees":
      result = await collectFees({ arm, provider });
      break;
    case "setARMBuffer":
      if (!args.buffer) {
        console.error("--buffer is required for setARMBuffer");
        process.exit(1);
      }
      result = await setARMBuffer({
        arm,
        buffer: Number(args.buffer),
      });
      break;
    default:
      console.error(`Unknown action: ${args.action}`);
      process.exit(1);
  }

  const encoded = encodeResult(result);
  process.stdout.write(encoded);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
