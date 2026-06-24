const { logTxDetails } = require("../utils/txLogger");

// Claim one or more matured LP redeem requests on behalf of users (the ARM
// operator is allowed to claim for any withdrawer; funds go to the withdrawer).
// `ids` is a comma-separated string of request ids, eg "12,13,14" (a single id
// like "12" also works). Each id is claimed independently: a failure on one id
// (already claimed, delay not met, insufficient liquidity, ...) is logged and the
// remaining ids are still attempted. The action throws at the end if any failed.
const claimArmRedeems = async ({ arm, armName, ids, log }) => {
  const requestIds = String(ids)
    .split(",")
    .map((id) => id.trim())
    .filter((id) => id.length > 0);

  if (requestIds.length === 0) {
    throw new Error("No request ids provided (use --ids 12,13,14)");
  }

  log.info(
    `Claiming ${requestIds.length} LP redeem request(s) from ${armName} ARM: ${requestIds}`,
  );

  const failed = [];
  for (const id of requestIds) {
    try {
      const tx = await arm.claimRedeem(id);
      await logTxDetails(tx, `claimRedeem ${id}`);
    } catch (err) {
      failed.push(id);
      log.error(
        `Failed to claim request ${id}: ${err?.shortMessage ?? err?.message ?? err}`,
      );
    }
  }

  if (failed.length > 0) {
    throw new Error(
      `Failed to claim ${failed.length}/${requestIds.length} request(s): ${failed}`,
    );
  }
};

module.exports = { claimArmRedeems };
