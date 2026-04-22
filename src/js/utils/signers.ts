import { JsonRpcProvider, Signer, Wallet } from "ethers";
import { Defender } from "@openzeppelin/defender-sdk";
import * as hhHelpers from "@nomicfoundation/hardhat-network-helpers";
import {
  createDb,
  createPool,
  wrapSignerWithNonceQueueV6,
} from "@talos/client";

import { ethereumAddress, privateKey } from "./regex";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const log = require("./logger")("utils:signers");

// `@talos/client` ships without .d.ts so the ambient decl in
// src/js/types/talos-client.d.ts types imports as `any`; the Db handle
// is therefore typed loosely here but used opaquely.
let dbInstance: unknown = null;
function getNonceDb(): unknown {
  if (!process.env.DATABASE_URL) return null;
  if (!dbInstance) {
    const pool = createPool({ connectionString: process.env.DATABASE_URL });
    dbInstance = createDb(pool);
  }
  return dbInstance;
}

// Wrap a raw signer with the nonce-queue Proxy when DATABASE_URL is set.
// Dev / fork runs (DATABASE_URL unset) get the raw signer, preserving
// the gate invariant.
function maybeWrap<S extends Signer>(rawSigner: S): S {
  const db = getNonceDb();
  if (!db) return rawSigner;
  return wrapSignerWithNonceQueueV6(rawSigner, { db });
}

// Use `hre` global injected by Hardhat at runtime.
declare const hre: {
  ethers: {
    provider: JsonRpcProvider;
    getSigners: () => Promise<Signer[]>;
  };
};
declare const ethers: { provider: JsonRpcProvider };

// ---------------------------------------------------------------------------
// KMS signer
// ---------------------------------------------------------------------------

const DEFAULT_KMS_RELAYER_ID = "mrk-248128595151466bb7f7b9a56501a98f";
const AWS_KMS_REGION = "us-east-1";

function hasAwsKmsCredentials(): boolean {
  return !!process.env.AWS_ACCESS_KEY_ID && !!process.env.AWS_SECRET_ACCESS_KEY;
}

async function getKmsSigner(): Promise<Signer> {
  // Dynamic require so we don't pull in the AWS SDK when it's not needed.
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { DirectKmsTransactionSigner } = require("@lastdotnet/purrikey");
  const relayerId = process.env.KMS_RELAYER_ID || DEFAULT_KMS_RELAYER_ID;
  const signer = new DirectKmsTransactionSigner(
    relayerId,
    hre.ethers.provider,
    AWS_KMS_REGION,
  );
  log(
    `Using KMS signer ${await signer.getAddress()} from relayer-id "${relayerId}"`,
  );
  return signer as Signer;
}

// ---------------------------------------------------------------------------
// Defender relayer signer
// ---------------------------------------------------------------------------

type DefenderSpeed = "safeLow" | "average" | "fast" | "fastest";

async function getDefenderSigner(): Promise<Signer> {
  const speed = (process.env.SPEED || "fastest") as string;
  const validSpeeds: DefenderSpeed[] = [
    "safeLow",
    "average",
    "fast",
    "fastest",
  ];
  if (!validSpeeds.includes(speed as DefenderSpeed)) {
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
    speed: speed as DefenderSpeed,
    ethersVersion: "v6",
  });
  log(
    `Using Defender Relayer account ${await signer.getAddress()} from env vars DEFENDER_RELAYER_KEY and DEFENDER_RELAYER_SECRET`,
  );
  return signer as unknown as Signer;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Signer factory — resolves a signer based on available credentials.
 *
 * Resolution order:
 *  1. Explicit `address` parameter (returns provider signer for that address)
 *  2. `DEPLOYER_PRIVATE_KEY` env var (Wallet from private key)
 *  3. AWS KMS credentials (`AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`)
 *  4. `IMPERSONATE` env var (impersonate + fund on a fork)
 *  5. Defender Relayer (`DEFENDER_RELAYER_KEY` + `DEFENDER_RELAYER_SECRET`)
 *  6. First hardhat signer (from the configured network)
 *  7. Random wallet (last resort)
 */
export async function getSigner(address?: string): Promise<Signer> {
  if (address) {
    if (!address.match(ethereumAddress)) {
      throw new Error("Invalid format of address");
    }
    return await hre.ethers.provider.getSigner(address);
  }

  const pk = process.env.DEPLOYER_PRIVATE_KEY;
  if (pk) {
    if (!pk.match(privateKey)) {
      throw new Error("Invalid format of private key");
    }
    const wallet = new Wallet(pk, hre.ethers.provider);
    log(`Using signer ${await wallet.getAddress()} from private key`);
    return maybeWrap(wallet);
  }

  if (hasAwsKmsCredentials()) {
    return maybeWrap(await getKmsSigner());
  }

  if (process.env.IMPERSONATE) {
    const impersonateAddr = process.env.IMPERSONATE;
    if (!impersonateAddr.match(ethereumAddress)) {
      throw new Error(
        "Environment variable IMPERSONATE is an invalid Ethereum address or contract name",
      );
    }
    log(
      `Impersonating account ${impersonateAddr} from IMPERSONATE environment variable`,
    );
    return await impersonateAndFund(impersonateAddr);
  }

  // Defender Relayer
  if (process.env.DEFENDER_RELAYER_KEY && process.env.DEFENDER_RELAYER_SECRET) {
    return maybeWrap(await getDefenderSigner());
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

/**
 * Impersonate an account when connecting to a forked node.
 */
export async function impersonateAccount(account: string): Promise<Signer> {
  await hhHelpers.impersonateAccount(account);
  return await ethers.provider.getSigner(account);
}

/**
 * Impersonate an account and fund it with Ether when connecting to a forked node.
 */
export async function impersonateAndFund(
  account: string,
  amount: bigint = BigInt(10e18),
): Promise<Signer> {
  const signer = await impersonateAccount(account);
  log(`Funding account ${account} with ${amount} ETH`);
  await hhHelpers.setBalance(account, amount);
  return signer;
}
