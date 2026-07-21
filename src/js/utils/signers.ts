import { JsonRpcProvider, Signer, Wallet } from "ethers";
import * as hhHelpers from "@nomicfoundation/hardhat-network-helpers";
import {
  createDb,
  createPool,
  wrapSignerWithNonceQueueV6,
} from "@oplabs/talos-client";

import { ethereumAddress, privateKey } from "./regex";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const log = require("./logger")("utils:signers");

// `@oplabs/talos-client` ships without .d.ts so the ambient decl in
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

// New-org production EVM signing key (account 114563866192,
// alias talos-prod-evm-signer). Overridden by KMS_RELAYER_ID in prod.
const DEFAULT_KMS_RELAYER_ID = "f153abb3-12be-4fa4-be0d-bceeb796ff3e";
const AWS_KMS_REGION = "us-east-1";

function hasAwsKmsCredentials(): boolean {
  // Static IAM user creds (legacy / local dev).
  if (process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY) {
    return true;
  }
  // ECS task role: the SDK fetches temporary creds from the task metadata
  // endpoint at this URL. Set automatically by Fargate when a task role
  // is attached, so its presence is a reliable "KMS is reachable from
  // this process" signal — we don't need to inject static keys.
  if (
    process.env.AWS_CONTAINER_CREDENTIALS_RELATIVE_URI ||
    process.env.AWS_CONTAINER_CREDENTIALS_FULL_URI
  ) {
    return true;
  }
  return false;
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
 *  5. First hardhat signer (from the configured network)
 *  6. Random wallet (last resort)
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
