const orderPendingUnstakerStates = (
  states,
  totalRequests,
  maxUnstakers,
  blockNumber,
) => {
  const activeStates = states.filter((state) => state.shares > 0n);
  if (activeStates.length === 0) return [];

  const pendingCount = BigInt(activeStates.length);
  if (pendingCount > totalRequests) {
    throw new Error("Ethena pending request count exceeds total requests");
  }

  const statesByIndex = new Map(
    activeStates.map((state) => [state.index, state]),
  );
  // The adapter clears requests only from the FIFO head, so the active request
  // ids are the final `pendingCount` ids and map to unstakers circularly.
  const firstPendingRequest = totalRequests - pendingCount;

  return Array.from({ length: activeStates.length }, (_, offset) => {
    const requestIndex = firstPendingRequest + BigInt(offset);
    const unstakerIndex = Number(requestIndex % maxUnstakers);
    const state = statesByIndex.get(unstakerIndex);
    if (!state) {
      const blockContext =
        blockNumber === undefined ? "" : ` at block ${blockNumber}`;
      throw new Error(
        `Missing Ethena unstaker ${unstakerIndex} for pending request ${requestIndex}${blockContext}`,
      );
    }
    return state;
  });
};

const selectClaimableFifoPrefix = (states) => {
  const firstUnreadyIndex = states.findIndex((state) => !state.isReady);
  if (firstUnreadyIndex === -1) return states;
  return states.slice(0, firstUnreadyIndex);
};

module.exports = {
  orderPendingUnstakerStates,
  selectClaimableFifoPrefix,
};
