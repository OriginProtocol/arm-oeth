const assert = require("assert");

const { AbiCoder, Contract, id } = require("ethers");

const { getOutstandingWithdrawals } = require("../../src/js/utils/arm");

const coder = AbiCoder.defaultAbiCoder();

const selector = (signature) => id(signature).slice(0, 10);

const providerRevert = () => {
  const err = new Error("execution reverted");
  err.name = "ProviderError";
  return err;
};

const run = async () => {
  const selectors = {
    reservedWithdrawLiquidity: selector("reservedWithdrawLiquidity()"),
    withdrawsQueued: selector("withdrawsQueued()"),
    withdrawsClaimed: selector("withdrawsClaimed()"),
  };

  {
    const runner = {
      call: async (tx) => {
        if (tx.data === selectors.reservedWithdrawLiquidity) {
          throw providerRevert();
        }
        if (tx.data === selectors.withdrawsQueued) {
          return coder.encode(["uint256"], [123n]);
        }
        if (tx.data === selectors.withdrawsClaimed) {
          return coder.encode(["uint256"], [23n]);
        }
        throw new Error(`unexpected selector ${tx.data}`);
      },
    };

    const arm = new Contract(
      "0x0000000000000000000000000000000000000001",
      ["function reservedWithdrawLiquidity() view returns (uint256)"],
      runner,
    );

    assert.strictEqual(await getOutstandingWithdrawals(arm), 100n);
  }

  {
    const runner = {
      call: async (tx) => {
        if (tx.data === selectors.reservedWithdrawLiquidity) {
          throw providerRevert();
        }
        if (
          tx.data === selectors.withdrawsQueued ||
          tx.data === selectors.withdrawsClaimed
        ) {
          const err = providerRevert();
          err.code = "CALL_EXCEPTION";
          throw err;
        }
        throw new Error(`unexpected selector ${tx.data}`);
      },
    };

    const arm = new Contract(
      "0x0000000000000000000000000000000000000001",
      ["function reservedWithdrawLiquidity() view returns (uint256)"],
      runner,
    );

    await assert.rejects(
      () => getOutstandingWithdrawals(arm),
      /Unable to read outstanding withdrawals for ARM .*reservedWithdrawLiquidity\(\).*legacy ABI withdrawsQueued\(\)\/withdrawsClaimed\(\) failed/,
    );
  }
};

run().then(() => console.log("arm tests passed"));
