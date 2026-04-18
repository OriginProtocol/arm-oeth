import type { Pool, PoolClient } from "pg";
import type { Signer, TransactionResponse } from "ethers";
import type { Logger } from "winston";
import {
  isNonceMismatchError,
  recoverNonceFromChain,
  submitNonceQueuedTransaction,
} from "./nonceQueueTxLifecycle";

let pool: Pool | null = null;
let tableEnsurePromise: Promise<void> | null = null;

function getNonceQueueLockTimeoutSeconds(log: Logger): number {
  const value = process.env.NONCE_QUEUE_LOCK_TIMEOUT_S;
  if (!value) return 0;

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0) {
    log.warn(
      `Invalid NONCE_QUEUE_LOCK_TIMEOUT_S="${value}" (expected integer >= 0). Falling back to 0 (wait forever).`,
    );
    return 0;
  }

  return parsed;
}

export function getNoncePool(): Pool | null {
  if (!process.env.DATABASE_URL) return null;
  if (!pool) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { Pool: PgPool } = require("pg");
    pool = new PgPool({
      connectionString: process.env.DATABASE_URL,
      max: 5,
      connectionTimeoutMillis: 120_000,
    });
  }
  return pool;
}

function ensureNonceTable(p: Pool): Promise<void> {
  if (!tableEnsurePromise) {
    tableEnsurePromise = p
      .query(
        `
      CREATE TABLE IF NOT EXISTS nonce_queue (
        signer_address TEXT NOT NULL,
        chain_id INTEGER NOT NULL,
        nonce INTEGER NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY (signer_address, chain_id)
      )
    `,
      )
      .then(() => {});
  }
  return tableEnsurePromise;
}

async function ensureNonceRow(
  client: PoolClient,
  signerAddress: string,
  chainId: number,
  getOnChainNonce: () => Promise<number>,
  log: Logger,
): Promise<void> {
  const { rows } = await client.query(
    "SELECT 1 FROM nonce_queue WHERE signer_address = $1 AND chain_id = $2",
    [signerAddress, chainId],
  );
  if (rows.length === 0) {
    const onChainNonce = await getOnChainNonce();
    log.info("Initializing nonce row", {
      event: "nonce.init",
      signer_address: signerAddress,
      chain_id: chainId,
      nonce: onChainNonce,
    });
    await client.query(
      `INSERT INTO nonce_queue (signer_address, chain_id, nonce)
       VALUES ($1, $2, $3)
       ON CONFLICT DO NOTHING`,
      [signerAddress, chainId, onChainNonce],
    );
  }
}

function isLockTimeoutError(err: any): boolean {
  const msg = (err?.message ?? "").toLowerCase();
  return (
    err?.code === "55P03" ||
    msg.includes("lock timeout") ||
    msg.includes("canceling statement due to lock timeout")
  );
}

async function withNonceLock<T>(
  p: Pool,
  signerAddress: string,
  chainId: number,
  getOnChainNonce: () => Promise<number>,
  log: Logger,
  fn: (nonce: number) => Promise<T>,
  maxRetries = 3,
): Promise<T> {
  await ensureNonceTable(p);
  const meta = { signer_address: signerAddress, chain_id: chainId };

  for (let attempt = 0; attempt < maxRetries; attempt++) {
    const client = await p.connect();
    const lockTimeoutSeconds = getNonceQueueLockTimeoutSeconds(log);
    try {
      await client.query("BEGIN");
      if (lockTimeoutSeconds > 0) {
        await client.query("SELECT set_config('lock_timeout', $1, true)", [
          `${lockTimeoutSeconds}s`,
        ]);
      }
      await ensureNonceRow(
        client,
        signerAddress,
        chainId,
        getOnChainNonce,
        log,
      );

      const { rows } = await client.query(
        "SELECT nonce FROM nonce_queue WHERE signer_address = $1 AND chain_id = $2 FOR UPDATE",
        [signerAddress, chainId],
      );
      const nonce: number = rows[0].nonce;

      log.info("Acquired nonce lock", {
        event: "nonce.lock.acquired",
        ...meta,
        nonce,
      });

      const result = await fn(nonce);

      await client.query(
        "UPDATE nonce_queue SET nonce = nonce + 1, updated_at = NOW() WHERE signer_address = $1 AND chain_id = $2",
        [signerAddress, chainId],
      );
      await client.query("COMMIT");

      log.info("Released nonce lock", {
        event: "nonce.lock.released",
        ...meta,
        nonce,
        next_nonce: nonce + 1,
      });

      return result;
    } catch (err: any) {
      await client.query("ROLLBACK").catch(() => {});

      if (isLockTimeoutError(err)) {
        const configuredTimeout =
          lockTimeoutSeconds > 0
            ? `${lockTimeoutSeconds}s`
            : "Postgres default";
        log.warn("Nonce lock timeout", {
          event: "nonce.lock.timeout",
          ...meta,
          timeout: configuredTimeout,
        });
      }

      if (isNonceMismatchError(err)) {
        log.warn(
          `Nonce mismatch (attempt ${attempt + 1}/${maxRetries}), recovering from chain`,
          {
            event: "nonce.mismatch",
            ...meta,
            attempt: attempt + 1,
            max_retries: maxRetries,
          },
        );
        await recoverNonceFromChain({
          pool: p,
          signerAddress,
          chainId,
          getOnChainNonce,
          log,
        });
        if (attempt < maxRetries - 1) continue;
      }

      throw err;
    } finally {
      client.release();
    }
  }

  throw new Error("withNonceLock: max retries exhausted");
}

/** Reset module state. Only for testing. */
export function _resetForTesting() {
  tableEnsurePromise = null;
  pool = null;
}

/**
 * Wraps an ethers v6 Signer so that every `sendTransaction` call is
 * serialized through a Postgres row lock. The nonce is managed by the
 * database — not by the provider. The lock is held until the transaction
 * is confirmed on-chain, so concurrent processes block rather than collide.
 *
 * If DATABASE_URL is not set, the signer is returned unmodified.
 */
export function wrapWithNonceQueue(
  signer: Signer,
  chainId: number,
  log: Logger,
): Signer {
  const p = getNoncePool();
  if (!p) return signer;

  const originalSendTransaction = signer.sendTransaction.bind(signer);
  const addressPromise = signer.getAddress().then((a) => a.toLowerCase());
  const getOnChainNonce = () => signer.getNonce("pending");

  signer.sendTransaction = async function (
    transaction: Parameters<typeof originalSendTransaction>[0],
  ): Promise<TransactionResponse> {
    const signerAddress = await addressPromise;
    return withNonceLock(
      p,
      signerAddress,
      chainId,
      getOnChainNonce,
      log,
      async (nonce) => {
        return submitNonceQueuedTransaction({
          sendTransaction: originalSendTransaction,
          provider: signer.provider ?? undefined,
          transaction,
          nonce,
          signerAddress,
          chainId,
          log,
        });
      },
    );
  };

  return signer;
}
