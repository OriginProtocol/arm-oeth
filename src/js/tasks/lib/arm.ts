import { ethers } from "ethers";
import type { Signer } from "ethers";

import { mainnet } from "../../utils/addresses";
const ethenaARMAbi = require("../../../abis/EthenaARM.json");
const etherFiARMAbi = require("../../../abis/EtherFiARM.json");
const lidoARMAbi = require("../../../abis/LidoARM.json");
const multiAssetARMAbi = require("../../../abis/MultiAssetARM.json");
const originARMAbi = require("../../../abis/OriginARM.json");

// decimals is the ARM's liquidity asset decimals. eg 18 for WETH, 6 for USDC.
const MAINNET_ARMS = {
  ethena: {
    abi: ethenaARMAbi,
    address: mainnet.ethenaARM,
    name: "Ethena",
    decimals: 18,
  },
  etherfi: {
    abi: etherFiARMAbi,
    address: mainnet.etherfiARM,
    name: "EtherFi",
    decimals: 18,
  },
  lido: {
    abi: lidoARMAbi,
    address: mainnet.lidoARM,
    name: "Lido",
    decimals: 18,
  },
  oeth: {
    abi: originARMAbi,
    address: mainnet.OethARM,
    name: "OETH",
    decimals: 18,
  },
  usd: {
    abi: multiAssetARMAbi,
    address: mainnet.usdARM,
    name: "USD",
    decimals: 6,
  },
};

type MainnetArmKey = keyof typeof MAINNET_ARMS;
const MAINNET_ARM_KEYS: MainnetArmKey[] = [
  "lido",
  "etherfi",
  "ethena",
  "oeth",
  "usd",
];

function formatSupportedArms(supportedArms: MainnetArmKey[]) {
  if (supportedArms.length <= 1) return supportedArms.join("");

  return `${supportedArms.slice(0, -1).join(", ")}, or ${
    supportedArms[supportedArms.length - 1]
  }`;
}

export function resolveMainnetARM({
  arm,
  signer,
  supportedArms = MAINNET_ARM_KEYS,
}: {
  arm: string;
  signer: Signer;
  supportedArms?: MainnetArmKey[];
}) {
  const armKey = arm.toLowerCase() as MainnetArmKey;
  const armConfig = MAINNET_ARMS[armKey];

  if (!armConfig || !supportedArms.includes(armKey)) {
    throw new Error(
      `Unsupported ARM "${arm}" (use ${formatSupportedArms(supportedArms)})`,
    );
  }

  return {
    ...armConfig,
    contract: new ethers.Contract(armConfig.address, armConfig.abi, signer),
  };
}
