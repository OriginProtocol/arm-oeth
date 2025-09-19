const { Wallet } = require("ethers");
const { Defender } = require("@openzeppelin/defender-sdk");
const hhHelpers = require("@nomicfoundation/hardhat-network-helpers");

const { ethereumAddress, privateKey } = require("./regex");

const log = require("./logger")("utils:signers");

/**
 * Signer factory that gets a signer for a hardhat test or task
 * If address is passed, use that address as signer.
 * If DEPLOYER_PK or GOVERNOR_PK is set, use that private key as signer.
 * If a fork and IMPERSONATE is set, impersonate that account.
 * else get the first signer from the hardhat node.
 * @param {*} address optional address of the signer
 * @returns
 */
async function getSigner(address = undefined) {
  if (address) {
    if (!address.match(ethereumAddress)) {
      throw Error(`Invalid format of address`);
    }
    return await hre.ethers.provider.getSigner(address);
  }
  const pk = process.env.DEPLOYER_PRIVATE_KEY;
  if (pk) {
    if (!pk.match(privateKey)) {
      throw Error(`Invalid format of private key`);
    }
    const wallet = new Wallet(pk, hre.ethers.provider);
    log(`Using signer ${await wallet.getAddress()} from private key`);
    return wallet;
  }

  if (process.env.IMPERSONATE) {
    let address = process.env.IMPERSONATE;
    if (!address.match(ethereumAddress)) {
      throw Error(
        `Environment variable IMPERSONATE is an invalid Ethereum address or contract name`,
      );
    }
    log(
      `Impersonating account ${address} from IMPERSONATE environment variable`,
    );
    return await impersonateAndFund(address);
  }

  // If using Defender Relayer
  if (process.env.DEFENDER_RELAYER_KEY && process.env.DEFENDER_RELAYER_SECRET) {
    return await getDefenderSigner();
  }

  const signers = await hre.ethers.getSigners();
  if (signers[0]) {
    const signer = signers[0];
    log(`Using the first hardhat signer ${await signer.getAddress()}`);
    return signer;
  }

  const signer = Wallet.createRandom().connect(hre.ethers.provider);
  log(`Using random signer ${await signer.getAddress()}`);

  return signer;
}

const getDefenderSigner = async () => {
  const speed = process.env.SPEED || "fastest";
  if (!["safeLow", "average", "fast", "fastest"].includes(speed)) {
    console.error(
      `Defender Relay Speed param must be either 'safeLow', 'average', 'fast' or 'fastest'. Not "${speed}"`,
    );
    process.exit(2);
  }
  const credentials = {
    relayerApiKey: process.env.DEFENDER_RELAYER_KEY,
    relayerApiSecret: process.env.DEFENDER_RELAYER_SECRET,
  };
  const client = new Defender(credentials);
  const provider = client.relaySigner.getProvider({ ethersVersion: "v6" });

  const signer = await client.relaySigner.getSigner(provider, {
    speed,
    ethersVersion: "v6",
  });
  log(
    `Using Defender Relayer account ${await signer.getAddress()} from env vars DEFENDER_RELAYER_KEY and DEFENDER_RELAYER_SECRET`,
  );
  return signer;
};

/**
 * Impersonate an account when connecting to a forked node.
 * @param {*} account the address of the contract or externally owned account to impersonate
 * @returns an Ethers.js Signer object
 */
async function impersonateAccount(account) {
  await hhHelpers.impersonateAccount(account);

  return await ethers.provider.getSigner(account);
}

/**
 * Impersonate an account and fund it with Ether when connecting to a forked node.
 * @param {*} account the address of the contract or externally owned account to impersonate
 * @amount the amount of Ether to fund the account with. This will be converted to wei.
 * @returns an Ethers.js Signer object
 */
async function impersonateAndFund(account, amount = BigInt(10e18)) {
  const signer = await impersonateAccount(account);

  log(`Funding account ${account} with ${amount} ETH`);
  await hhHelpers.setBalance(account, amount);

  return signer;
}

module.exports = {
  getSigner,
  impersonateAccount,
  impersonateAndFund,
};
