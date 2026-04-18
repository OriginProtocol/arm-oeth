import type { Provider, Signer, TransactionResponse } from "ethers";
import { Transaction } from "ethers";
import type { Pool, PoolClient } from "pg";
import type { Logger } from "winston";

const GWEI = 1_000_000_000n;
const DEFAULT_PRIORITY_FEE = GWEI * 2n;
const DEFAULT_GAS_PRICE = GWEI * 20n;

export interface SubmitNonceQueuedTxParams {
  sendTransaction: (
    transaction: Parameters<Signer["sendTransaction"]>[0],
  ) => Promise<TransactionResponse>;
  provider?: Provider;
  transaction: Parameters<Signer["sendTransaction"]>[0];
  nonce: number;
  signerAddress: string;
  chainId: number;
  log: Logger;
}

interface TxLifecycleConfig {
  txConfirmTimeoutS: number;
  receiptPollS: number;
  rebroadcastIntervalS: number;
  replaceIntervalS: number;
  maxReplacements: number;
  feeBumpPct: number;
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parseIntEnv(
  log: Logger,
  name: string,
  fallback: number,
  minimum = 0,
  maximum?: number,
): number {
  const value = process.env[name];
  if (!value) return fallback;

  const parsed = Number(value);
  const withinMax = maximum === undefined || parsed <= maximum;
  if (!Number.isInteger(parsed) || parsed < minimum || !withinMax) {
    const maxMsg = maximum === undefined ? "" : ` and <= ${maximum}`;
    log.warn(
      `Invalid ${name}="${value}" (expected integer >= ${minimum}${maxMsg}). Falling back to ${fallback}.`,
    );
    return fallback;
  }
  return parsed;
}

function getTxLifecycleConfig(log: Logger): TxLifecycleConfig {
  return {
    txConfirmTimeoutS: parseIntEnv(
      log,
      "NONCE_QUEUE_TX_CONFIRM_TIMEOUT_S",
      600,
    ),
    receiptPollS: parseIntEnv(log, "NONCE_QUEUE_RECEIPT_POLL_S", 5, 1),
    rebroadcastIntervalS: parseIntEnv(
      log,
      "NONCE_QUEUE_REBROADCAST_INTERVAL_S",
      30,
    ),
    replaceIntervalS: parseIntEnv(log, "NONCE_QUEUE_REPLACE_INTERVAL_S", 90),
    maxReplacements: parseIntEnv(log, "NONCE_QUEUE_MAX_REPLACEMENTS", 3),
    feeBumpPct: parseIntEnv(log, "NONCE_QUEUE_FEE_BUMP_PCT", 15, 0, 500),
  };
}

function secondsToMs(seconds: number): number {
  return seconds * 1_000;
}

function asBigInt(value: any): bigint | undefined {
  if (value === undefined || value === null) return undefined;
  try {
    return BigInt(value);
  } catch {
    return undefined;
  }
}

function bumpByPercent(value: bigint, percent: number): bigint {
  if (percent === 0) return value;
  return (value * BigInt(100 + percent) + 99n) / 100n;
}

function maxBigInt(a: bigint, b: bigint): bigint {
  return a >= b ? a : b;
}

function getTxCapComparableGasPrice(
  transaction: Parameters<Signer["sendTransaction"]>[0],
): bigint | undefined {
  return (
    asBigInt((transaction as any).maxFeePerGas) ??
    asBigInt((transaction as any).gasPrice)
  );
}

function getPerChainMaxGasPriceEnvKey(chainId: number): string {
  return `NONCE_QUEUE_MAX_GAS_PRICE_GWEI_CHAIN_${chainId}`;
}

function resolveMaxGasPriceWeiForChain(
  chainId: number,
  log: Logger,
): bigint | null {
  const envKey = getPerChainMaxGasPriceEnvKey(chainId);
  const value = process.env[envKey];
  if (!value) return null;

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0) {
    log.warn(
      `Invalid ${envKey}="${value}" (expected integer >= 0). Gas cap disabled for chain ${chainId}.`,
    );
    return null;
  }
  if (parsed === 0) return null;
  return GWEI * BigInt(parsed);
}

function assertWithinGasPriceCap({
  priceWei,
  maxGasPriceWei,
  maxGasPriceEnvKey,
  stage,
  signerAddress,
  chainId,
  nonce,
}: {
  priceWei: bigint;
  maxGasPriceWei: bigint;
  maxGasPriceEnvKey: string;
  stage: "initial submission" | "rebroadcast" | "replacement";
  signerAddress: string;
  chainId: number;
  nonce: number;
}) {
  if (priceWei <= maxGasPriceWei) return;
  throw new Error(
    `Nonce queue gas price cap exceeded during ${stage}: address=${signerAddress} chain=${chainId} nonce=${nonce} gasPrice=${priceWei.toString()} wei cap=${maxGasPriceWei.toString()} wei (set by ${maxGasPriceEnvKey})`,
  );
}

async function enforceSubmissionGasPriceCap({
  transaction,
  provider,
  maxGasPriceWei,
  maxGasPriceEnvKey,
  stage,
  signerAddress,
  chainId,
  nonce,
}: {
  transaction: Parameters<Signer["sendTransaction"]>[0];
  provider?: Provider;
  maxGasPriceWei: bigint | null;
  maxGasPriceEnvKey: string;
  stage: "initial submission" | "replacement";
  signerAddress: string;
  chainId: number;
  nonce: number;
}) {
  if (!maxGasPriceWei) return;

  let comparableGasPrice = getTxCapComparableGasPrice(transaction);
  if (!comparableGasPrice && provider) {
    const feeData = await provider.getFeeData().catch(() => null);
    comparableGasPrice =
      asBigInt(feeData?.maxFeePerGas) ?? asBigInt(feeData?.gasPrice);
  }

  if (!comparableGasPrice) {
    throw new Error(
      `Unable to enforce ${maxGasPriceEnvKey} for ${stage}: address=${signerAddress} chain=${chainId} nonce=${nonce} transaction has no gasPrice/maxFeePerGas and provider fee data is unavailable`,
    );
  }

  assertWithinGasPriceCap({
    priceWei: comparableGasPrice,
    maxGasPriceWei,
    maxGasPriceEnvKey,
    stage,
    signerAddress,
    chainId,
    nonce,
  });
}

function enforceRebroadcastGasPriceCap({
  rawTransaction,
  maxGasPriceWei,
  maxGasPriceEnvKey,
  signerAddress,
  chainId,
  nonce,
}: {
  rawTransaction: string;
  maxGasPriceWei: bigint | null;
  maxGasPriceEnvKey: string;
  signerAddress: string;
  chainId: number;
  nonce: number;
}) {
  if (!maxGasPriceWei) return;

  const parsedTransaction = Transaction.from(rawTransaction);
  const comparableGasPrice =
    asBigInt(parsedTransaction.maxFeePerGas) ??
    asBigInt(parsedTransaction.gasPrice);

  if (!comparableGasPrice) {
    throw new Error(
      `Unable to enforce ${maxGasPriceEnvKey} for rebroadcast: address=${signerAddress} chain=${chainId} nonce=${nonce} raw transaction has no gasPrice/maxFeePerGas`,
    );
  }

  assertWithinGasPriceCap({
    priceWei: comparableGasPrice,
    maxGasPriceWei,
    maxGasPriceEnvKey,
    stage: "rebroadcast",
    signerAddress,
    chainId,
    nonce,
  });
}

function extractRawTransaction(
  response: TransactionResponse,
): string | undefined {
  const candidate =
    (response as any).raw ??
    (response as any).rawTransaction ??
    (response as any).serialized;
  return typeof candidate === "string" && candidate.length > 0
    ? candidate
    : undefined;
}

function isDuplicateBroadcastError(err: any): boolean {
  const msg = (err?.message ?? "").toLowerCase();
  return (
    msg.includes("already known") ||
    msg.includes("known transaction") ||
    msg.includes("already imported")
  );
}

async function findMinedReceipt(provider: Provider, hashes: string[]) {
  for (const hash of hashes) {
    const receipt = await provider.getTransactionReceipt(hash);
    if (receipt) return receipt;
  }
  return null;
}

async function buildReplacementTransaction(
  transaction: Parameters<Signer["sendTransaction"]>[0],
  provider: Provider,
  feeBumpPct: number,
): Promise<Parameters<Signer["sendTransaction"]>[0]> {
  const feeData = await provider.getFeeData().catch(() => null);
  const nextTx: any = { ...transaction };

  const hasEip1559Fees =
    nextTx.maxFeePerGas !== undefined ||
    nextTx.maxPriorityFeePerGas !== undefined ||
    nextTx.type === 2;

  if (hasEip1559Fees) {
    const basePriority =
      asBigInt(nextTx.maxPriorityFeePerGas) ??
      asBigInt(feeData?.maxPriorityFeePerGas) ??
      DEFAULT_PRIORITY_FEE;
    const baseMaxFee =
      asBigInt(nextTx.maxFeePerGas) ??
      asBigInt(feeData?.maxFeePerGas) ??
      basePriority * 2n;

    const bumpedPriority = bumpByPercent(basePriority, feeBumpPct);
    const bumpedMaxFee = bumpByPercent(baseMaxFee, feeBumpPct);
    const networkPriority = asBigInt(feeData?.maxPriorityFeePerGas);
    const networkMaxFee = asBigInt(feeData?.maxFeePerGas);

    let finalPriority = bumpedPriority;
    let finalMaxFee = bumpedMaxFee;
    if (networkPriority) {
      finalPriority = maxBigInt(finalPriority, networkPriority);
    }
    if (networkMaxFee) {
      finalMaxFee = maxBigInt(finalMaxFee, networkMaxFee);
    }
    if (finalMaxFee < finalPriority) {
      finalMaxFee = finalPriority;
    }

    delete nextTx.gasPrice;
    nextTx.maxPriorityFeePerGas = finalPriority;
    nextTx.maxFeePerGas = finalMaxFee;
    nextTx.type = 2;
    return nextTx;
  }

  const baseGasPrice =
    asBigInt(nextTx.gasPrice) ??
    asBigInt(feeData?.gasPrice) ??
    DEFAULT_GAS_PRICE;
  const networkGasPrice = asBigInt(feeData?.gasPrice);
  let finalGasPrice = bumpByPercent(baseGasPrice, feeBumpPct);
  if (networkGasPrice) {
    finalGasPrice = maxBigInt(finalGasPrice, networkGasPrice);
  }
  nextTx.gasPrice = finalGasPrice;
  return nextTx;
}

/**
 * Send a nonce-pinned transaction and wait for on-chain confirmation.
 * Handles rebroadcast of raw tx, same-nonce replacement with bumped fees,
 * and per-chain gas price caps.
 */
export async function submitNonceQueuedTransaction({
  sendTransaction,
  provider,
  transaction,
  nonce,
  signerAddress,
  chainId,
  log,
}: SubmitNonceQueuedTxParams): Promise<TransactionResponse> {
  const config = getTxLifecycleConfig(log);
  const maxGasPriceEnvKey = getPerChainMaxGasPriceEnvKey(chainId);
  const maxGasPriceWei = resolveMaxGasPriceWeiForChain(chainId, log);
  const meta = { signer_address: signerAddress, chain_id: chainId };
  const initialTx: any = {
    ...transaction,
    nonce,
  };

  await enforceSubmissionGasPriceCap({
    transaction: initialTx,
    provider,
    maxGasPriceWei,
    maxGasPriceEnvKey,
    stage: "initial submission",
    signerAddress,
    chainId,
    nonce,
  });

  const firstResponse = await sendTransaction(initialTx);
  const responsesByHash = new Map<string, TransactionResponse>([
    [firstResponse.hash, firstResponse],
  ]);
  const knownHashes: string[] = [firstResponse.hash];
  let activeTx = initialTx;
  let activeResponse = firstResponse;
  let activeRawTx = extractRawTransaction(firstResponse);
  let replacementCount = 0;
  let rebroadcastRawUnavailableLogged = false;

  log.info("Submitted tx", {
    event: "nonce.tx.submitted",
    ...meta,
    nonce,
    tx_hash: firstResponse.hash,
  });

  if (!provider || typeof provider.getTransactionReceipt !== "function") {
    await firstResponse.wait();
    return firstResponse;
  }
  const txProvider = provider;

  const startedAt = Date.now();
  let nextRebroadcastAt =
    config.rebroadcastIntervalS > 0
      ? startedAt + secondsToMs(config.rebroadcastIntervalS)
      : Number.POSITIVE_INFINITY;
  let nextReplaceAt =
    config.replaceIntervalS > 0
      ? startedAt + secondsToMs(config.replaceIntervalS)
      : Number.POSITIVE_INFINITY;

  while (true) {
    const receipt = await findMinedReceipt(txProvider, knownHashes);
    if (receipt) {
      if (receipt.status === 0) {
        throw new Error(
          `Nonce-queued transaction reverted on-chain: hash=${receipt.hash} nonce=${nonce}`,
        );
      }
      return responsesByHash.get(receipt.hash) ?? activeResponse;
    }

    const now = Date.now();
    if (
      config.txConfirmTimeoutS > 0 &&
      now - startedAt >= secondsToMs(config.txConfirmTimeoutS)
    ) {
      throw new Error(
        `Timed out waiting for nonce-queued tx confirmation after ${config.txConfirmTimeoutS}s: address=${signerAddress} chain=${chainId} nonce=${nonce} lastHash=${activeResponse.hash}`,
      );
    }

    if (now >= nextRebroadcastAt) {
      nextRebroadcastAt = now + secondsToMs(config.rebroadcastIntervalS);

      if (
        activeRawTx &&
        typeof txProvider.broadcastTransaction === "function"
      ) {
        try {
          enforceRebroadcastGasPriceCap({
            rawTransaction: activeRawTx,
            maxGasPriceWei,
            maxGasPriceEnvKey,
            signerAddress,
            chainId,
            nonce,
          });
          const rebroadcastResponse =
            await txProvider.broadcastTransaction(activeRawTx);
          if (!responsesByHash.has(rebroadcastResponse.hash)) {
            responsesByHash.set(rebroadcastResponse.hash, rebroadcastResponse);
            knownHashes.push(rebroadcastResponse.hash);
          }
          log.info("Rebroadcasted raw tx", {
            event: "nonce.tx.rebroadcast",
            ...meta,
            nonce,
            tx_hash: rebroadcastResponse.hash,
          });
        } catch (err: any) {
          if (!isDuplicateBroadcastError(err)) throw err;
          log.info("Rebroadcast ignored duplicate", {
            event: "nonce.tx.rebroadcast.duplicate",
            ...meta,
            nonce,
            tx_hash: activeResponse.hash,
          });
        }
      } else if (!rebroadcastRawUnavailableLogged) {
        rebroadcastRawUnavailableLogged = true;
        log.warn("Rebroadcast skipped: raw transaction payload unavailable", {
          ...meta,
          nonce,
          tx_hash: activeResponse.hash,
        });
      }
    }

    if (
      now >= nextReplaceAt &&
      replacementCount < config.maxReplacements &&
      config.replaceIntervalS > 0
    ) {
      nextReplaceAt = now + secondsToMs(config.replaceIntervalS);
      activeTx = await buildReplacementTransaction(
        activeTx,
        txProvider,
        config.feeBumpPct,
      );
      await enforceSubmissionGasPriceCap({
        transaction: activeTx,
        provider: txProvider,
        maxGasPriceWei,
        maxGasPriceEnvKey,
        stage: "replacement",
        signerAddress,
        chainId,
        nonce,
      });

      try {
        const replacementResponse = await sendTransaction(activeTx);
        replacementCount++;
        activeResponse = replacementResponse;
        activeRawTx = extractRawTransaction(replacementResponse);
        if (!responsesByHash.has(replacementResponse.hash)) {
          responsesByHash.set(replacementResponse.hash, replacementResponse);
          knownHashes.push(replacementResponse.hash);
        }
        log.info("Submitted replacement tx", {
          event: "nonce.tx.replacement",
          ...meta,
          nonce,
          tx_hash: replacementResponse.hash,
          replacement_count: replacementCount,
          max_replacements: config.maxReplacements,
        });
      } catch (err: any) {
        if (!isNonceMismatchError(err) && !isDuplicateBroadcastError(err)) {
          throw err;
        }
        log.warn("Replacement attempt not accepted", {
          event: "nonce.tx.replacement.rejected",
          ...meta,
          nonce,
          error_message: err?.message ?? String(err),
        });
      }
    }

    await sleep(secondsToMs(config.receiptPollS));
  }
}

export function isNonceMismatchError(err: any): boolean {
  const msg = (err?.message ?? "").toLowerCase();
  return (
    msg.includes("nonce too low") ||
    msg.includes("nonce has already been used") ||
    msg.includes("replacement transaction underpriced")
  );
}

export async function recoverNonceFromChain({
  pool,
  signerAddress,
  chainId,
  getOnChainNonce,
  client,
  log,
}: {
  pool: Pool;
  signerAddress: string;
  chainId: number;
  getOnChainNonce: () => Promise<number>;
  client?: PoolClient;
  log: Logger;
}) {
  const onChainNonce = await getOnChainNonce();
  const recoveryClient = client ?? (await pool.connect());
  const usingExternalClient = !!client;

  try {
    await recoveryClient.query(
      "UPDATE nonce_queue SET nonce = $1, updated_at = NOW() WHERE signer_address = $2 AND chain_id = $3",
      [onChainNonce, signerAddress, chainId],
    );
    log.info("Recovered nonce from chain", {
      event: "nonce.recovered",
      signer_address: signerAddress,
      chain_id: chainId,
      nonce: onChainNonce,
    });
  } finally {
    if (!usingExternalClient) recoveryClient.release();
  }
}
