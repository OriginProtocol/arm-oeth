const ARM_NAME_ALIASES = {
  lido: "Lido",
  etherfi: "EtherFi",
  ether_fi: "EtherFi",
  "ether-fi": "EtherFi",
  ethena: "Ethena",
  oeth: "Oeth",
  origin: "Origin",
  usd: "USD",
};

const ARM_DEPLOY_NAMES = {
  EtherFi: "ETHER_FI_ARM",
  Oeth: "OETH_ARM",
  USD: "USD_ARM",
};

const ARM_CONTRACT_NAMES = {
  Oeth: "OriginARM",
  USD: "MultiAssetARM",
};

const normalizeArmName = (arm) => {
  if (!arm) return arm;
  const armName = arm.toString();
  const normalized = armName.replace(/\s+/g, "").toLowerCase();
  return ARM_NAME_ALIASES[normalized] ?? armName;
};

const deployNameForArm = (arm) => {
  const armName = normalizeArmName(arm);
  return ARM_DEPLOY_NAMES[armName] ?? `${armName.toUpperCase()}_ARM`;
};

const contractNameForArm = (arm) => {
  const armName = normalizeArmName(arm);
  return ARM_CONTRACT_NAMES[armName] ?? `${armName}ARM`;
};

module.exports = {
  contractNameForArm,
  deployNameForArm,
  normalizeArmName,
};
