const assert = require("assert");

const { AbiCoder, Contract, id } = require("ethers");

const {
  etherFiRequestStatuses,
  selectClaimableEtherFiRequests,
} = require("../../src/js/tasks/etherfiQueue");

const coder = AbiCoder.defaultAbiCoder();

const selector = (signature) => id(signature).slice(0, 10);

const run = async () => {
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
