import { JsonRpcProvider, Signer } from "ethers";
import * as hhHelpers from "@nomicfoundation/hardhat-network-helpers";
import { resolveEthersV6Signer } from "@automaton/client";

import { ethereumAddress } from "./regex";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const log = require("./logger")("utils:signers");

// Use `hre` global injected by Hardhat at runtime.
declare const hre: {
  ethers: {
    provider: JsonRpcProvider;
    getSigners: () => Promise<Signer[]>;
  };
};
declare const ethers: { provider: JsonRpcProvider };

/**
 * Signer factory.
 *
 * Resolution order:
 *  1. Explicit `address` parameter — return the provider signer for that
 *     address (hardhat-native; used by fork tests).
 *  2. `IMPERSONATE` env var — impersonate + fund that address on a fork.
 *  3. Otherwise delegate to `@automaton/client`'s `resolveEthersV6Signer`,
 *     which auto-detects strategy from env:
 *       - AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY present
 *         → KMS signer (KMS_RELAYER_ID, default Origin production key)
 *       - else → private key (DEPLOYER_PRIVATE_KEY / DEPLOYER_PK /
 *         GOVERNOR_PK / ANVIL_PRIVATE_KEY, in that order)
 *       - else → anvil account #0 (local dev)
 */
export async function getSigner(address?: string): Promise<Signer> {
  if (address) {
    if (!address.match(ethereumAddress)) {
      throw new Error("Invalid format of address");
    }
    return await hre.ethers.provider.getSigner(address);
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

  const signer = await resolveEthersV6Signer(hre.ethers.provider);
  log(
    `Using signer ${await signer.getAddress()} (resolved by @automaton/client)`,
  );
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
