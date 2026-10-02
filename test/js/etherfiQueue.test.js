const assert = require("assert");
const { Request, Response } = require("node-fetch");
const { createApolloClient } = require("../../src/js/utils/apollo");

const { AbiCoder, Contract, id, parseUnits } = require("ethers");

const {
  queryEtherFiWithdrawalRequests,
  etherFiRequestStatuses,
  selectClaimableEtherFiRequests,
  splitEtherFiWithdrawAmount,
} = require("../../src/js/tasks/etherfiQueue");

const coder = AbiCoder.defaultAbiCoder();

const selector = (signature) => id(signature).slice(0, 10);

const run = async () => {
  // Exercise the lookup through Apollo's real HTTP link to verify its error
  // shapes and that a failed query can actually be retried on the same client.
  const lookup = async (responses) => {
    let calls = 0;
    const waits = [];
    const client = createApolloClient(
      "https://example.com/graphql",
      async (url, options) => {
        // Verify the shared client disables compression at the HTTP link.
        const request = new Request(url, options);
        assert.strictEqual(request.headers.get("accept-encoding"), "identity");
        assert.strictEqual(request.compress, false);
        const response = responses[calls++];
        if (response instanceof Error) throw response;
        assert.ok(response, "unexpected query attempt");
        return new Response(JSON.stringify(response.body), {
          status: response.status,
          headers: { "content-type": "application/json" },
        });
      },
    );
    try {
      const ids = await queryEtherFiWithdrawalRequests(client, async (ms) => {
        waits.push(ms);
      });
      return { ids, calls, waits };
    } catch (error) {
      return { error, calls, waits };
    }
  };
  const success = {
    status: 200,
    body: { data: { etherfiWithdrawalRequests: [{ requestId: "83121" }] } },
  };
  const unavailable = {
    status: 503,
    body: { errors: [{ message: "Service unavailable" }] },
  };
  {
    const result = await lookup([unavailable, success]);
    assert.deepStrictEqual(result, { ids: ["83121"], calls: 2, waits: [1000] });
  }
  {
    const result = await lookup([new Error("connection reset"), success]);
    assert.deepStrictEqual(result, { ids: ["83121"], calls: 2, waits: [1000] });
  }
  {
    const rateLimited = {
      status: 429,
      body: { errors: [{ message: "Too many requests" }] },
    };
    const result = await lookup([rateLimited, rateLimited, rateLimited]);
    assert.strictEqual(result.calls, 3);
    assert.deepStrictEqual(result.waits, [1000, 2000]);
    assert.match(
      result.error.message,
      /attempt 3\/3.*HTTP 429.*Too many requests/,
    );
    assert.strictEqual(result.error.cause.networkError.statusCode, 429);
  }
  {
    const result = await lookup([
      {
        status: 200,
        body: { errors: [{ message: "Unknown field claimable" }] },
      },
    ]);
    assert.strictEqual(result.calls, 1);
    assert.deepStrictEqual(result.waits, []);
    assert.match(result.error.message, /Unknown field claimable/);
    assert.ok(result.error.cause);
  }
  {
    const result = await lookup([
      { status: 401, body: { errors: [{ message: "Unauthorized" }] } },
    ]);
    assert.strictEqual(result.calls, 1);
    assert.deepStrictEqual(result.waits, []);
    assert.match(result.error.message, /HTTP 401.*Unauthorized/);
  }
  {
    const result = await lookup([
      { status: 200, body: { data: { etherfiWithdrawalRequests: [] } } },
    ]);
    assert.deepStrictEqual(result, { ids: [], calls: 1, waits: [] });
  }

  // Ether.fi rejects individual withdrawal requests above 1,000 eETH.
  assert.deepStrictEqual(splitEtherFiWithdrawAmount(parseUnits("1000")), [
    parseUnits("1000"),
  ]);
  assert.deepStrictEqual(splitEtherFiWithdrawAmount(parseUnits("1971.5")), [
    parseUnits("1000"),
    parseUnits("971.5"),
  ]);
  assert.deepStrictEqual(splitEtherFiWithdrawAmount(parseUnits("2000")), [
    parseUnits("1000"),
    parseUnits("1000"),
  ]);
  // weETH uses the adapter-provided share amount equivalent to 1,000 eETH.
  assert.deepStrictEqual(
    splitEtherFiWithdrawAmount(parseUnits("1800"), parseUnits("950")),
    [parseUnits("950"), parseUnits("850")],
  );

  // Pure filter: finalized AND still valid on-chain is the only claimable state.
  {
    const statuses = [
      // Already claimed: the NFT is burnt so isValid is false even though
      // EtherFi still reports isFinalized true. Regression for the recurring
      // "ERC721: invalid token ID" failure (mainnet request 80636).
      { requestId: 80636, isFinalized: true, isValid: false },
      // Requested but not yet finalized: valid but can't be claimed yet.
      { requestId: 80648, isFinalized: false, isValid: true },
      // Genuinely claimable.
      { requestId: 80641, isFinalized: true, isValid: true },
    ];

    assert.deepStrictEqual(selectClaimableEtherFiRequests(statuses), [80641]);
  }

  // End-to-end status read + filter against a mock WithdrawRequestNFT, proving
  // the stale request 80636 that wedged autoClaimEtherFiWithdraw is dropped.
  {
    const selectors = {
      isFinalized: selector("isFinalized(uint256)"),
      getRequest: selector("getRequest(uint256)"),
    };
    const requestId = (data) => BigInt(`0x${data.slice(10)}`).toString();

    // isFinalized mirrors lastFinalizedRequestId: true for ids <= 80647.
    const finalizedById = { 80636: true, 80641: true, 80648: false };
    // isValid is false for the already-claimed/burnt 80636.
    const validById = { 80636: false, 80641: true, 80648: true };

    const runner = {
      call: async (tx) => {
        const fn = tx.data.slice(0, 10);
        const key = requestId(tx.data);
        if (fn === selectors.isFinalized) {
          return coder.encode(["bool"], [finalizedById[key]]);
        }
        if (fn === selectors.getRequest) {
          return coder.encode(
            ["tuple(uint96,uint96,bool,uint32)"],
            [[0n, 0n, validById[key], 0]],
          );
        }
        throw new Error(`unexpected selector ${tx.data}`);
      },
    };

    const withdrawalNFT = new Contract(
      "0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c",
      [
        "function isFinalized(uint256 requestId) view returns (bool)",
        "function getRequest(uint256 requestId) view returns (tuple(uint96 amountOfEEth, uint96 shareOfEEth, bool isValid, uint32 feeGwei))",
      ],
      runner,
    );

    const statuses = await etherFiRequestStatuses(
      withdrawalNFT,
      [80636, 80641, 80648],
    );

    assert.deepStrictEqual(selectClaimableEtherFiRequests(statuses), [80641]);
  }
};

run()
  .then(() => console.log("etherfiQueue tests passed"))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
