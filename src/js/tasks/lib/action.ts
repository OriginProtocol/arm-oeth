import { randomUUID } from "node:crypto";
import type { Signer } from "ethers";
import { subtask, task } from "hardhat/config";
import type { ConfigurableTaskDefinition } from "hardhat/types";
import type { Logger } from "winston";
import {
  createDb,
  createPool,
  type Db,
  wrapSignerWithNonceQueueV6,
} from "@automaton/client";

import { getSigner as defaultGetSigner } from "../../utils/signers";
import logger, { flushLogger } from "./logger";

let dbInstance: Db | null = null;
function getNonceDb(): Db | null {
  if (!process.env.DATABASE_URL) return null;
  if (!dbInstance) {
    const pool = createPool({ connectionString: process.env.DATABASE_URL });
    dbInstance = createDb(pool);
  }
  return dbInstance;
}

export interface ActionContext {
  signer: Signer;
  chainId: number;
  networkName: string;
  log: Logger;
  args: Record<string, any>;
}

export interface ActionConfig {
  name: string;
  description: string;
  chains?: number[];
  params?: (t: ConfigurableTaskDefinition) => void;
  run: (ctx: ActionContext) => Promise<void>;
}

export interface ActionDeps {
  getSigner?: () => Promise<Signer>;
}

const CHAIN_NAMES: Record<number, string> = {
  1: "mainnet",
  146: "sonic",
  17000: "holesky",
};

export function createActionHandler(
  config: ActionConfig,
  deps: ActionDeps = {},
) {
  const { name, chains, run } = config;
  const getSigner = deps.getSigner ?? defaultGetSigner;

  return async (taskArgs: Record<string, any>) => {
    const runId = randomUUID();
    const log = logger.child({ action: name, run_id: runId });
    const startTime = Date.now();
    let chainId: number | undefined;
    let networkName: string | undefined;

    try {
      const rawSigner = await getSigner();
      const network = await rawSigner.provider!.getNetwork();
      chainId = Number(network.chainId);
      const db = getNonceDb();
      const signer = db
        ? wrapSignerWithNonceQueueV6(rawSigner, { db, log })
        : rawSigner;
      networkName = CHAIN_NAMES[chainId] ?? `unknown-${chainId}`;

      log.info(`Running on ${networkName} (${chainId})`, {
        event: "action.start",
        source: "task",
        chain_id: chainId,
        network: networkName,
      });

      if (chains && !chains.includes(chainId)) {
        const valid = chains
          .map((id) => `${CHAIN_NAMES[id] ?? id} (${id})`)
          .join(", ");
        throw new Error(
          `${name} only supports ${valid}, not ${networkName} (${chainId})`,
        );
      }

      await run({ signer, chainId, networkName, log, args: taskArgs });
      log.info(
        `Completed in ${((Date.now() - startTime) / 1000).toFixed(1)}s`,
        {
          event: "action.success",
          source: "task",
          chain_id: chainId,
          network: networkName,
          duration_ms: Date.now() - startTime,
        },
      );
    } catch (err: any) {
      log.error(`${err?.name ?? "Error"}: ${err?.message ?? String(err)}`, {
        event: "action.error",
        source: "task",
        chain_id: chainId,
        network: networkName,
        duration_ms: Date.now() - startTime,
        error_name: err?.name ?? "Error",
        error_message: err?.message ?? String(err),
        error_stack: err?.stack,
      });
      throw err;
    } finally {
      await flushLogger();
    }
  };
}

export function action(config: ActionConfig) {
  const handler = createActionHandler(config);

  const definition = subtask(config.name, config.description);
  if (config.params) {
    config.params(definition);
  }
  definition.setAction(handler);

  task(config.name).setAction(async (_, __, runSuper) => {
    return runSuper();
  });
}
