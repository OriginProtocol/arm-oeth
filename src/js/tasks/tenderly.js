const fetch = require("node-fetch");
const { readFileSync } = require("fs");
const path = require("path");

const { parseDeployedAddress } = require("../utils/addressParser");

async function tenderlyUpload({ name }) {
  const address = await parseDeployedAddress(name);
  const { chainId } = await ethers.provider.getNetwork();

  await uploadContractToTenderly(address, name, chainId);
}

async function tenderlySync() {
  const deployedContracts = await loadDeployedContracts();
  const { chainId } = await ethers.provider.getNetwork();
  const allTenderlyContracts = await fetchAllContractsFromTenderly();

  for (let i = 0; i < deployedContracts.length; i++) {
    let presentInTenderly = false;
    const deployedContract = deployedContracts[i];

    for (let j = 0; j < allTenderlyContracts.length; j++) {
      if (
        deployedContract.address.toLowerCase() ===
        allTenderlyContracts[j].toLowerCase()
      ) {
        presentInTenderly = true;
      }
    }

    if (presentInTenderly) {
      console.log(
        `✓ contract ${deployedContract.name}[${deployedContract.address}] already detected by Tenderly`,
      );
      continue;
    }

    await uploadContractToTenderly(
      deployedContract.address,
      deployedContract.name,
      chainId,
    );
    console.log(
      `✅ contract ${deployedContract.name}[${deployedContract.address}] added to Tenderly`,
    );
  }
}

async function loadDeployedContracts() {
  const { chainId } = await ethers.provider.getNetwork();
  const fileName = path.join(
    process.cwd(),
    "build",
    `deployments-${chainId}.json`,
  );
  const deploymentData = JSON.parse(readFileSync(fileName, "utf-8"));

  return (deploymentData.contracts || []).map((contract) => ({
    name: contract.name,
    address: contract.implementation,
  }));
}

async function uploadContractToTenderly(address, name, networkId) {
  if (!process.env.TENDERLY_ACCESS_TOKEN) {
    throw new Error("TENDERLY_ACCESS_TOKEN env var missing");
  }

  const baseUrl =
    "https://api.tenderly.co/api/v1/account/origin-protocol/project/origin/address";

  const payload = {
    network_id: `${networkId}`,
    address,
    display_name: name,
  };

  const response = await fetch(baseUrl, {
    method: "POST",
    headers: {
      "X-Access-Key": `${process.env.TENDERLY_ACCESS_TOKEN}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    throw new Error(
      `API request failed with status ${
        response.status
      }: ${await response.text()}`,
    );
  }

  return await response.json();
}

async function fetchAllContractsFromTenderly() {
  if (!process.env.TENDERLY_ACCESS_TOKEN) {
    throw new Error("TENDERLY_ACCESS_TOKEN env var missing");
  }

  const baseUrl =
    "https://api.tenderly.co/api/v1/account/origin-protocol/project/origin/contracts?accountType=contract";

  const response = await fetch(baseUrl, {
    method: "GET",
    headers: {
      "X-Access-Key": `${process.env.TENDERLY_ACCESS_TOKEN}`,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    throw new Error(
      `API request failed with status ${
        response.status
      }: ${await response.text()}`,
    );
  }

  const data = await response.json();
  return data.map((contractData) => contractData.contract.address);
}

module.exports = {
  tenderlySync,
  tenderlyUpload,
};
