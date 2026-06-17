import { AbiCoder } from "ethers";
import type { Signer } from "ethers";
import { subtask, task } from "hardhat/config";
import type { ConfigurableTaskDefinition } from "hardhat/types";

import { getSigner as defaultGetSigner } from "../../utils/signers";

export interface Logger {
  info(msg: unknown, ...rest: unknown[]): void;
  warn(msg: unknown, ...rest: unknown[]): void;
  error(msg: unknown, ...rest: unknown[]): void;
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

const abiCoder = AbiCoder.defaultAbiCoder();

function tryParseJson(value: unknown): unknown {
  if (typeof value !== "string") return undefined;
  try {
    return JSON.parse(value);
  } catch {
    return undefined;
  }
}

function findRevertData(err: unknown): string | undefined {
  const seen = new Set<unknown>();
  const queue: unknown[] = [err];

  while (queue.length > 0) {
    const item = queue.shift();
    if (!item || seen.has(item)) continue;
    seen.add(item);

    if (typeof item === "string") {
      const parsed = tryParseJson(item);
      if (parsed) queue.push(parsed);
      continue;
    }

    if (typeof item !== "object") continue;
    const record = item as Record<string, unknown>;

    if (typeof record.data === "string" && record.data.startsWith("0x")) {
      return record.data;
    }

    queue.push(
      record.data,
      record.error,
      record.info,
      record.body,
      record.cause,
      record.receipt,
    );

    const info = record.info as Record<string, unknown> | undefined;
    if (info?.error) queue.push(info.error);
  }

  return undefined;
}

function decodeRevertData(data: string): string | undefined {
  if (data === "0x") return "empty revert data";

  if (data.startsWith("0x08c379a0")) {
    try {
      const [reason] = abiCoder.decode(["string"], `0x${data.slice(10)}`);
      return `Error("${reason}")`;
    } catch {}
  }

  if (data.startsWith("0x4e487b71")) {
    try {
      const [code] = abiCoder.decode(["uint256"], `0x${data.slice(10)}`);
      return `Panic(${code})`;
    } catch {}
  }

  return `custom/unknown error selector ${data.slice(0, 10)} data ${data}`;
}

function describeRevert(err: unknown): string | undefined {
  const data = findRevertData(err);
  return data ? decodeRevertData(data) : undefined;
}

function makeLog(name: string): Logger {
  const prefix = `[${name}]`;
  return {
    info: (msg, ...rest) => console.log(prefix, msg, ...rest),
    warn: (msg, ...rest) => console.warn(prefix, msg, ...rest),
    error: (msg, ...rest) => console.error(prefix, msg, ...rest),
  };
}

export function createActionHandler(
  config: ActionConfig,
  deps: ActionDeps = {},
) {
  const { name, chains, run } = config;
  const getSigner = deps.getSigner ?? defaultGetSigner;

  return async (taskArgs: Record<string, any>) => {
    const log = makeLog(name);
    const startTime = Date.now();
    let chainId: number | undefined;
    let networkName: string | undefined;

    try {
      // Signer already wraps sendTransaction with the nonce queue when
      // DATABASE_URL is set — see utils/signers.ts. Helper modules that
      // call getSigner() directly get the same wrapped signer.
      const signer = await getSigner();
      const network = await signer.provider!.getNetwork();
      chainId = Number(network.chainId);
      networkName = CHAIN_NAMES[chainId] ?? `unknown-${chainId}`;

      log.info(`Running on ${networkName} (${chainId})`);

      if (chains && !chains.includes(chainId)) {
        const valid = chains
          .map((id) => `${CHAIN_NAMES[id] ?? id} (${id})`)
          .join(", ");
        throw new Error(
          `${name} only supports ${valid}, not ${networkName} (${chainId})`,
        );
      }

      await run({ signer, chainId, networkName, log, args: taskArgs });
      log.info(`Completed in ${((Date.now() - startTime) / 1000).toFixed(1)}s`);
    } catch (err: any) {
      log.error(`${err?.name ?? "Error"}: ${err?.message ?? String(err)}`);
      const revert = describeRevert(err);
      if (revert) log.error(`Contract revert: ${revert}`);
      if (err?.stack) log.error(err.stack);
      throw err;
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
