import { Wallet } from "ethers";
import type { Logger } from "winston";

import { submitNonceQueuedTransaction } from "./nonceQueueTxLifecycle";

const mockLog = {
  info: () => {},
  warn: () => {},
  error: () => {},
  child: () => mockLog,
} as unknown as Logger;

type EnvOverrides = Record<string, string | undefined>;
const MAINNET_GAS_CAP_ENV = "NONCE_QUEUE_MAX_GAS_PRICE_GWEI_CHAIN_1";

function makeResponse(hash: string, raw?: string): any {
  return {
    hash,
    raw,
    rawTransaction: raw,
    wait: async () => ({ status: 1, transactionHash: hash }),
  };
}

async function withEnv<T>(overrides: EnvOverrides, fn: () => Promise<T>) {
  const previousValues: Record<string, string | undefined> = {};
  for (const key of Object.keys(overrides)) {
    previousValues[key] = process.env[key];
  }

  for (const [key, value] of Object.entries(overrides)) {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }

  try {
    return await fn();
  } finally {
    for (const [key, value] of Object.entries(previousValues)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}

const GWEI = 1_000_000_000n;

async function testReplacementPath() {
  console.log("--- Lifecycle Test 1: Replacement path fee bump ---");

  const sentTxs: any[] = [];
  let sendCount = 0;
  const signerSendTransaction = async (tx: any) => {
    sentTxs.push(tx);
    if (sendCount === 0) {
      sendCount++;
      return makeResponse("0xinitial", "0xraw-initial");
    }
    sendCount++;
    return makeResponse("0xreplacement", "0xraw-replacement");
  };

  let receiptChecks = 0;
  const provider: any = {
    async getTransactionReceipt(hash: string) {
      receiptChecks++;
      if (hash === "0xreplacement" && receiptChecks >= 4) {
        return { status: 1, hash: "0xreplacement" };
      }
      return null;
    },
    async getFeeData() {
      return {
        maxFeePerGas: 400n,
        maxPriorityFeePerGas: 5n,
      };
    },
    async broadcastTransaction() {
      throw new Error("rebroadcast disabled in this test");
    },
  };

  const result = await withEnv(
    {
      NONCE_QUEUE_TX_CONFIRM_TIMEOUT_S: "20",
      NONCE_QUEUE_RECEIPT_POLL_S: "1",
      NONCE_QUEUE_REBROADCAST_INTERVAL_S: "0",
      NONCE_QUEUE_REPLACE_INTERVAL_S: "1",
      NONCE_QUEUE_MAX_REPLACEMENTS: "2",
      NONCE_QUEUE_FEE_BUMP_PCT: "20",
    },
    () =>
      submitNonceQueuedTransaction({
        sendTransaction: signerSendTransaction as any,
        provider,
        transaction: {
          to: "0x0000000000000000000000000000000000000001",
          data: "0x",
          maxFeePerGas: 100n,
          maxPriorityFeePerGas: 2n,
        } as any,
        nonce: 7,
        signerAddress: "0xaaaa",
        chainId: 1,
        log: mockLog,
      }),
  );

  if (result.hash !== "0xreplacement") {
    throw new Error(`Expected replacement hash, got ${result.hash}`);
  }
  if (sentTxs.length < 2) {
    throw new Error(`Expected at least 2 submissions, got ${sentTxs.length}`);
  }
  if (sentTxs[1].nonce !== 7) {
    throw new Error(`Expected replacement nonce=7, got ${sentTxs[1].nonce}`);
  }
  if (!(BigInt(sentTxs[1].maxFeePerGas) > BigInt(sentTxs[0].maxFeePerGas))) {
    throw new Error("Expected replacement maxFeePerGas to increase");
  }
  if (
    !(
      BigInt(sentTxs[1].maxPriorityFeePerGas) >=
      BigInt(sentTxs[0].maxPriorityFeePerGas)
    )
  ) {
    throw new Error("Expected replacement maxPriorityFeePerGas to increase");
  }

  console.log("PASS: replacement submitted with same nonce and higher fees\n");
}

async function testTimeoutPath() {
  console.log("--- Lifecycle Test 2: Confirmation timeout path ---");

  const signerSendTransaction = async () => makeResponse("0xtimeout");
  const provider: any = {
    async getTransactionReceipt() {
      return null;
    },
    async getFeeData() {
      return {};
    },
    async broadcastTransaction() {
      return makeResponse("0xnever");
    },
  };

  let timeoutError: Error | undefined;
  await withEnv(
    {
      NONCE_QUEUE_TX_CONFIRM_TIMEOUT_S: "2",
      NONCE_QUEUE_RECEIPT_POLL_S: "1",
      NONCE_QUEUE_REBROADCAST_INTERVAL_S: "0",
      NONCE_QUEUE_REPLACE_INTERVAL_S: "0",
    },
    async () => {
      try {
        await submitNonceQueuedTransaction({
          sendTransaction: signerSendTransaction as any,
          provider,
          transaction: {
            to: "0x0000000000000000000000000000000000000001",
            data: "0x",
          } as any,
          nonce: 11,
          signerAddress: "0xbbbb",
          chainId: 1,
          log: mockLog,
        });
      } catch (err: any) {
        timeoutError = err;
      }
    },
  );

  if (!timeoutError) {
    throw new Error("Expected timeout error but transaction did not fail");
  }
  if (!timeoutError.message.includes("after 2s")) {
    throw new Error(
      `Unexpected timeout error message: ${timeoutError.message}`,
    );
  }

  console.log("PASS: confirmation timeout errors as expected\n");
}

async function testRebroadcastPath() {
  console.log("--- Lifecycle Test 3: Rebroadcast duplicate handling ---");

  const signerSendTransaction = async () =>
    makeResponse("0xrebroadcast", "0xraw-rebroadcast");

  let rebroadcastAttempts = 0;
  let receiptChecks = 0;
  const provider: any = {
    async getTransactionReceipt(hash: string) {
      receiptChecks++;
      if (hash === "0xrebroadcast" && receiptChecks >= 3) {
        return { status: 1, hash: "0xrebroadcast" };
      }
      return null;
    },
    async getFeeData() {
      return {};
    },
    async broadcastTransaction() {
      rebroadcastAttempts++;
      throw new Error("already known");
    },
  };

  const result = await withEnv(
    {
      NONCE_QUEUE_TX_CONFIRM_TIMEOUT_S: "10",
      NONCE_QUEUE_RECEIPT_POLL_S: "1",
      NONCE_QUEUE_REBROADCAST_INTERVAL_S: "1",
      NONCE_QUEUE_REPLACE_INTERVAL_S: "0",
    },
    () =>
      submitNonceQueuedTransaction({
        sendTransaction: signerSendTransaction as any,
        provider,
        transaction: {
          to: "0x0000000000000000000000000000000000000001",
          data: "0x",
        } as any,
        nonce: 12,
        signerAddress: "0xcccc",
        chainId: 1,
        log: mockLog,
      }),
  );

  if (result.hash !== "0xrebroadcast") {
    throw new Error(`Expected original hash, got ${result.hash}`);
  }
  if (rebroadcastAttempts < 1) {
    throw new Error("Expected at least one rebroadcast attempt");
  }

  console.log("PASS: rebroadcast duplicate errors are handled\n");
}

async function testInitialSubmissionGasCap() {
  console.log("--- Lifecycle Test 4: Initial submission per-chain gas cap ---");

  let sendCalls = 0;
  const signerSendTransaction = async () => {
    sendCalls++;
    return makeResponse("0xshould-not-send");
  };
  const provider: any = {
    async getFeeData() {
      return {};
    },
  };

  let capError: Error | undefined;
  await withEnv(
    {
      [MAINNET_GAS_CAP_ENV]: "20",
      NONCE_QUEUE_MAX_GAS_PRICE_GWEI: undefined,
      NONCE_QUEUE_TX_CONFIRM_TIMEOUT_S: "10",
      NONCE_QUEUE_RECEIPT_POLL_S: "1",
      NONCE_QUEUE_REBROADCAST_INTERVAL_S: "0",
      NONCE_QUEUE_REPLACE_INTERVAL_S: "0",
    },
    async () => {
      try {
        await submitNonceQueuedTransaction({
          sendTransaction: signerSendTransaction as any,
          provider,
          transaction: {
            to: "0x0000000000000000000000000000000000000001",
            data: "0x",
            gasPrice: 25n * GWEI,
          } as any,
          nonce: 21,
          signerAddress: "0xdddd",
          chainId: 1,
          log: mockLog,
        });
      } catch (err: any) {
        capError = err;
      }
    },
  );

  if (!capError) {
    throw new Error("Expected initial submission gas cap error");
  }
  if (!capError.message.includes("initial submission")) {
    throw new Error(`Unexpected gas cap error message: ${capError.message}`);
  }
  if (sendCalls !== 0) {
    throw new Error(
      `Expected sendTransaction not to be called, got ${sendCalls}`,
    );
  }

  console.log("PASS: initial submission over cap fails before sending\n");
}

async function testMissingChainSpecificCapDisablesEnforcement() {
  console.log(
    "--- Lifecycle Test 5: Missing chain-specific cap disables enforcement ---",
  );

  let sendCalls = 0;
  const signerSendTransaction = async () => {
    sendCalls++;
    return makeResponse("0xno-cap-chain");
  };

  const result = await withEnv(
    {
      [MAINNET_GAS_CAP_ENV]: "20",
      NONCE_QUEUE_MAX_GAS_PRICE_GWEI: undefined,
      NONCE_QUEUE_REBROADCAST_INTERVAL_S: "0",
      NONCE_QUEUE_REPLACE_INTERVAL_S: "0",
    },
    () =>
      submitNonceQueuedTransaction({
        sendTransaction: signerSendTransaction as any,
        transaction: {
          to: "0x0000000000000000000000000000000000000001",
          data: "0x",
          gasPrice: 25n * GWEI,
        } as any,
        nonce: 23,
        signerAddress: "0xffff",
        chainId: 146, // Sonic — no cap set for this chain
        log: mockLog,
      }),
  );

  if (result.hash !== "0xno-cap-chain") {
    throw new Error(`Expected successful tx hash, got ${result.hash}`);
  }
  if (sendCalls !== 1) {
    throw new Error(`Expected one send call, got ${sendCalls}`);
  }

  console.log("PASS: cap is disabled when chain-specific env is missing\n");
}

async function testReplacementGasCap() {
  console.log("--- Lifecycle Test 6: Replacement gas cap ---");

  const sentTxs: any[] = [];
  const signerSendTransaction = async (tx: any) => {
    sentTxs.push(tx);
    return makeResponse("0xreplacement-seed", "0xraw-replacement-seed");
  };

  const provider: any = {
    async getTransactionReceipt() {
      return null;
    },
    async getFeeData() {
      return {
        maxFeePerGas: 10n * GWEI,
        maxPriorityFeePerGas: 2n * GWEI,
      };
    },
    async broadcastTransaction() {
      throw new Error("rebroadcast disabled in replacement cap test");
    },
  };

  let capError: Error | undefined;
  await withEnv(
    {
      [MAINNET_GAS_CAP_ENV]: "12",
      NONCE_QUEUE_MAX_GAS_PRICE_GWEI: undefined,
      NONCE_QUEUE_TX_CONFIRM_TIMEOUT_S: "10",
      NONCE_QUEUE_RECEIPT_POLL_S: "1",
      NONCE_QUEUE_REBROADCAST_INTERVAL_S: "0",
      NONCE_QUEUE_REPLACE_INTERVAL_S: "1",
      NONCE_QUEUE_MAX_REPLACEMENTS: "2",
      NONCE_QUEUE_FEE_BUMP_PCT: "30",
    },
    async () => {
      try {
        await submitNonceQueuedTransaction({
          sendTransaction: signerSendTransaction as any,
          provider,
          transaction: {
            to: "0x0000000000000000000000000000000000000001",
            data: "0x",
            maxFeePerGas: 10n * GWEI,
            maxPriorityFeePerGas: 2n * GWEI,
            type: 2,
          } as any,
          nonce: 24,
          signerAddress: "0x1111",
          chainId: 1,
          log: mockLog,
        });
      } catch (err: any) {
        capError = err;
      }
    },
  );

  if (!capError) {
    throw new Error("Expected replacement gas cap error");
  }
  if (!capError.message.includes("replacement")) {
    throw new Error(`Unexpected replacement cap error: ${capError.message}`);
  }
  if (sentTxs.length !== 1) {
    throw new Error(
      `Expected only initial send to happen before replacement cap failure, got ${sentTxs.length}`,
    );
  }

  console.log("PASS: replacement over cap fails before sending replacement\n");
}

async function testRebroadcastGasCap() {
  console.log("--- Lifecycle Test 7: Rebroadcast gas cap ---");

  const wallet = new Wallet(
    "0x59c6995e998f97a5a0044966f0945388cf0f6e44f9c76c9d83f816f94f8f93f4",
  );
  const highGasTx = await wallet.signTransaction({
    to: "0x0000000000000000000000000000000000000001",
    nonce: 0,
    gasLimit: 21_000,
    gasPrice: 30n * GWEI,
    value: 0,
    chainId: 1,
    data: "0x",
  });

  let providerSendCalls = 0;
  const signerSendTransaction = async () => makeResponse("0xseed", highGasTx);
  const provider: any = {
    async getTransactionReceipt() {
      return null;
    },
    async getFeeData() {
      return {};
    },
    async broadcastTransaction() {
      providerSendCalls++;
      return makeResponse("0xrebroadcast-high");
    },
  };

  let capError: Error | undefined;
  await withEnv(
    {
      [MAINNET_GAS_CAP_ENV]: "20",
      NONCE_QUEUE_MAX_GAS_PRICE_GWEI: undefined,
      NONCE_QUEUE_TX_CONFIRM_TIMEOUT_S: "10",
      NONCE_QUEUE_RECEIPT_POLL_S: "1",
      NONCE_QUEUE_REBROADCAST_INTERVAL_S: "1",
      NONCE_QUEUE_REPLACE_INTERVAL_S: "0",
    },
    async () => {
      try {
        await submitNonceQueuedTransaction({
          sendTransaction: signerSendTransaction as any,
          provider,
          transaction: {
            to: "0x0000000000000000000000000000000000000001",
            data: "0x",
            gasPrice: 10n * GWEI,
          } as any,
          nonce: 22,
          signerAddress: "0xeeee",
          chainId: 1,
          log: mockLog,
        });
      } catch (err: any) {
        capError = err;
      }
    },
  );

  if (!capError) {
    throw new Error("Expected rebroadcast gas cap error");
  }
  if (!capError.message.includes("rebroadcast")) {
    throw new Error(`Unexpected rebroadcast cap error: ${capError.message}`);
  }
  if (providerSendCalls !== 0) {
    throw new Error(
      `Expected provider rebroadcast broadcastTransaction not to be called, got ${providerSendCalls}`,
    );
  }

  console.log("PASS: rebroadcast over cap fails with clear error\n");
}

async function testDeprecatedGlobalGasCapIgnored() {
  console.log("--- Lifecycle Test 8: Deprecated global gas cap is ignored ---");

  let sendCalls = 0;
  const signerSendTransaction = async () => {
    sendCalls++;
    return makeResponse("0xglobal-ignored");
  };

  const result = await withEnv(
    {
      [MAINNET_GAS_CAP_ENV]: undefined,
      NONCE_QUEUE_MAX_GAS_PRICE_GWEI: "1",
      NONCE_QUEUE_REBROADCAST_INTERVAL_S: "0",
      NONCE_QUEUE_REPLACE_INTERVAL_S: "0",
    },
    () =>
      submitNonceQueuedTransaction({
        sendTransaction: signerSendTransaction as any,
        transaction: {
          to: "0x0000000000000000000000000000000000000001",
          data: "0x",
          gasPrice: 50n * GWEI,
        } as any,
        nonce: 25,
        signerAddress: "0x2222",
        chainId: 1,
        log: mockLog,
      }),
  );

  if (result.hash !== "0xglobal-ignored") {
    throw new Error(`Expected tx success when only global cap is set`);
  }
  if (sendCalls !== 1) {
    throw new Error(`Expected one send call, got ${sendCalls}`);
  }

  console.log("PASS: deprecated global cap does not enforce lifecycle limit\n");
}

async function test() {
  await testReplacementPath();
  await testTimeoutPath();
  await testRebroadcastPath();
  await testInitialSubmissionGasCap();
  await testMissingChainSpecificCapDisablesEnforcement();
  await testReplacementGasCap();
  await testRebroadcastGasCap();
  await testDeprecatedGlobalGasCapIgnored();
  console.log("All nonceQueueTxLifecycle tests passed!");
}

test().catch((err) => {
  console.error("TEST FAILED:", err);
  process.exit(1);
});
