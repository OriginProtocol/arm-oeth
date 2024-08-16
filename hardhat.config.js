/** @type import('hardhat/config').HardhatUserConfig */

require("dotenv").config();

require("@nomiclabs/hardhat-ethers");
require("@nomicfoundation/hardhat-foundry");

require("./src/js/tasks/tasks");

module.exports = {
  networks: {
    mainnet: {
      url: `${process.env.PROVIDER_URL}`,
    },
    hardhat: {
      forking: {
        url: `${process.env.PROVIDER_URL}`,
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
