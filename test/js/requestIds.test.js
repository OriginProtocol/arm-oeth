const assert = require("assert");

const { parseRequestIds } = require("../../src/js/utils/requestIds");

const run = () => {
  assert.deepStrictEqual(parseRequestIds({}), undefined);
  assert.deepStrictEqual(parseRequestIds({ id: "81143" }), [81143n]);
  assert.deepStrictEqual(parseRequestIds({ ids: "81143, 81155,81158" }), [
    81143n,
    81155n,
    81158n,
  ]);
  assert.throws(
    () => parseRequestIds({ id: "81143", ids: "81155" }),
    /either id or ids/,
  );
  assert.throws(() => parseRequestIds({ ids: "81143,invalid" }), /Invalid/);
  assert.throws(
    () => parseRequestIds({ ids: "81155,81143" }),
    /ascending FIFO order/,
  );
};

try {
  run();
  console.log("requestIds tests passed");
} catch (error) {
  console.error(error);
  process.exitCode = 1;
}
