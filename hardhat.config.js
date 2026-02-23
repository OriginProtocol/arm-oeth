/** @type import('hardhat/config').HardhatUserConfig */

require("dotenv").config();

require("@nomicfoundation/hardhat-ethers");
require("@nomicfoundation/hardhat-foundry");

const { internalTask } = require("hardhat/config");
const {
  TASK_COMPILE_GET_REMAPPINGS,
  TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS,
} = require("hardhat/builtin-tasks/task-names");
const path = require("path");

// Override the remappings task to filter out context remappings (lines with ":"
// before "="). This is needed because Soldeer generates context remappings for
// dependencies that use different versions of the same library (e.g. Pendle SY)
// and hardhat-foundry doesn't support them.
internalTask(TASK_COMPILE_GET_REMAPPINGS).setAction(async (_, __, runSuper) => {
  const { exec } = require("child_process");
  const { promisify } = require("util");
  const execAsync = promisify(exec);

  const { stdout } = await execAsync("forge remappings");
  const remappings = {};

  for (const line of stdout.split(/\r\n|\r|\n/)) {
    if (line.trim() === "") continue;

    // Skip context remappings (contain ":" before "=")
    const eqIdx = line.indexOf("=");
    const colonIdx = line.indexOf(":");
    if (colonIdx !== -1 && (eqIdx === -1 || colonIdx < eqIdx)) continue;

    const [from, ...rest] = line.split("=");
    if (remappings[from] === undefined) {
      remappings[from] = rest.join("=");
    }
  }

  return remappings;
});

// Exclude Pendle SY contracts from Hardhat compilation since they require
// OZ 4.9.3 context remappings that Hardhat doesn't support.
internalTask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(
  async (_, __, runSuper) => {
    const paths = await runSuper();
    return paths.filter(
      (p) => !p.includes(path.join("contracts", "pendle") + path.sep),
    );
  },
);

require("./src/js/tasks/tasks");

module.exports = {
  networks: {
    mainnet: {
      url: `${process.env.MAINNET_URL}`,
    },
    hardhat: {
      forking: {
        url: `${process.env.MAINNET_URL}`,
        ...(process.env.BLOCK_NUMBER
          ? { blockNumber: process.env.BLOCK_NUMBER }
          : {}),
      },
    },
    local: {
      url: "http://localhost:8545",
    },
    holesky: {
      url: `${process.env.HOLESKY_URL}`,
      chainId: 17000,
    },
    sonic: {
      url: `${process.env.SONIC_URL}`,
      chainId: 146,
    },
    testnet: {
      url: `${process.env.TESTNET_URL}`,
      chainId: 1,
    },
  },
  solidity: "0.8.23",
  settings: {
    optimizer: {
      enabled: true,
    },
  },
  tracer: {
    tasks: ["snap", "swap"],
  },
};
