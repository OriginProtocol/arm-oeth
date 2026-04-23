const addresses = require("./addresses");

const ARM_PAIRS = {
  Oeth: { liquidity: "WETH", base: "OETH" },
  Origin: { liquidity: "WS", base: "OS" },
  Lido: { liquidity: "WETH", base: "stETH" },
  EtherFi: { liquidity: "WETH", base: "EETH" },
  Ethena: { liquidity: "USDE", base: "SUSDE" },
};

const config = {
  1: {
    Oeth: {
      venues: {
        kyber: { targetEnvVar: "MAINNET_OETH_KYBER_SWAP_TARGET" },
        "1inch": { targetEnvVar: "MAINNET_OETH_1INCH_SWAP_TARGET" },
        curve: {
          targetEnvVar: "MAINNET_OETH_CURVE_SWAP_TARGET",
          poolAddressEnvVar: "MAINNET_OETH_CURVE_POOL_ADDRESS",
          indices: { WETH: 0, OETH: 1 },
        },
        balancer: {
          targetEnvVar: "MAINNET_OETH_BALANCER_SWAP_TARGET",
          poolIdEnvVar: "MAINNET_OETH_BALANCER_POOL_ID",
        },
      },
    },
    Lido: {
      venues: {
        kyber: { targetEnvVar: "MAINNET_LIDO_KYBER_SWAP_TARGET" },
        "1inch": { targetEnvVar: "MAINNET_LIDO_1INCH_SWAP_TARGET" },
        curve: {
          targetEnvVar: "MAINNET_LIDO_CURVE_SWAP_TARGET",
          poolAddress: addresses.mainnet.CurveStEthPool,
          indices: { WETH: 0, stETH: 1 },
        },
        balancer: {
          targetEnvVar: "MAINNET_LIDO_BALANCER_SWAP_TARGET",
          poolIdEnvVar: "MAINNET_LIDO_BALANCER_POOL_ID",
        },
      },
    },
    EtherFi: {
      venues: {
        kyber: { targetEnvVar: "MAINNET_ETHERFI_KYBER_SWAP_TARGET" },
        "1inch": { targetEnvVar: "MAINNET_ETHERFI_1INCH_SWAP_TARGET" },
        curve: {
          targetEnvVar: "MAINNET_ETHERFI_CURVE_SWAP_TARGET",
          poolAddressEnvVar: "MAINNET_ETHERFI_CURVE_POOL_ADDRESS",
          indices: { WETH: 0, EETH: 1 },
        },
        balancer: {
          targetEnvVar: "MAINNET_ETHERFI_BALANCER_SWAP_TARGET",
          poolIdEnvVar: "MAINNET_ETHERFI_BALANCER_POOL_ID",
        },
      },
    },
    Ethena: {
      venues: {
        kyber: { targetEnvVar: "MAINNET_ETHENA_KYBER_SWAP_TARGET" },
        "1inch": { targetEnvVar: "MAINNET_ETHENA_1INCH_SWAP_TARGET" },
        curve: {
          targetEnvVar: "MAINNET_ETHENA_CURVE_SWAP_TARGET",
          poolAddressEnvVar: "MAINNET_ETHENA_CURVE_POOL_ADDRESS",
          indices: { USDE: 0, SUSDE: 1 },
        },
        balancer: {
          targetEnvVar: "MAINNET_ETHENA_BALANCER_SWAP_TARGET",
          poolIdEnvVar: "MAINNET_ETHENA_BALANCER_POOL_ID",
        },
      },
    },
  },
  146: {
    Origin: {
      venues: {
        kyber: { targetEnvVar: "SONIC_ORIGIN_KYBER_SWAP_TARGET" },
        "1inch": { targetEnvVar: "SONIC_ORIGIN_1INCH_SWAP_TARGET" },
        curve: {
          targetEnvVar: "SONIC_ORIGIN_CURVE_SWAP_TARGET",
          poolAddressEnvVar: "SONIC_ORIGIN_CURVE_POOL_ADDRESS",
          indices: { WS: 0, OS: 1 },
        },
        balancer: {
          targetEnvVar: "SONIC_ORIGIN_BALANCER_SWAP_TARGET",
          poolIdEnvVar: "SONIC_ORIGIN_BALANCER_POOL_ID",
        },
      },
    },
  },
};

const getArmPairConfig = (arm) => {
  const pairConfig = ARM_PAIRS[arm];
  if (!pairConfig) {
    throw new Error(
      `Unsupported ARM "${arm}". Use Oeth, Origin, Lido, EtherFi or Ethena`,
    );
  }
  return pairConfig;
};

const getVenueConfig = ({ chainId, arm, venue }) => {
  const chainConfig = config[Number(chainId)];
  if (!chainConfig?.[arm]?.venues?.[venue]) {
    throw new Error(
      `Unsupported venue "${venue}" for ARM "${arm}" on chain ${chainId}`,
    );
  }
  return chainConfig[arm].venues[venue];
};

const getRequiredEnv = (envVar) => {
  const value = process.env[envVar];
  if (!value) {
    throw new Error(`Missing required environment variable ${envVar}`);
  }
  return value;
};

module.exports = {
  getArmPairConfig,
  getVenueConfig,
  getRequiredEnv,
};
