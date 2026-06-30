import { ethers } from "ethers";
import type { Signer } from "ethers";

import { mainnet } from "../../utils/addresses";
const ethenaARMAbi = require("../../../abis/EthenaARM.json");
const etherFiARMAbi = require("../../../abis/EtherFiARM.json");
const lidoARMAbi = require("../../../abis/LidoARM.json");
const originARMAbi = require("../../../abis/OriginARM.json");

const MAINNET_ARMS = {
  ethena: {
    abi: ethenaARMAbi,
    address: mainnet.ethenaARM,
    name: "Ethena",
  },
  etherfi: {
    abi: etherFiARMAbi,
    address: mainnet.etherfiARM,
    name: "EtherFi",
  },
  lido: {
    abi: lidoARMAbi,
    address: mainnet.lidoARM,
    name: "Lido",
  },
  oeth: {
    abi: originARMAbi,
    address: mainnet.OethARM,
    name: "OETH",
  },
};

type MainnetArmKey = keyof typeof MAINNET_ARMS;
const MAINNET_ARM_KEYS: MainnetArmKey[] = ["lido", "etherfi", "ethena", "oeth"];

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
