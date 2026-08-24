const parseRequestIds = ({ id, ids }) => {
  if (id !== undefined && ids !== undefined) {
    throw new Error("Specify either id or ids, not both");
  }

  const requestIdInputs = ids ?? id;
  if (requestIdInputs === undefined) return undefined;

  const values = Array.isArray(requestIdInputs)
    ? requestIdInputs
    : requestIdInputs.toString().split(",");

  if (values.length === 0) {
    throw new Error("At least one withdrawal request id is required");
  }

  const requestIds = values.map((value) => {
    const requestId = value.toString().trim();
    if (!/^\d+$/.test(requestId)) {
      throw new Error(`Invalid withdrawal request id: ${value}`);
    }
    return BigInt(requestId);
  });

  for (let index = 1; index < requestIds.length; index++) {
    if (requestIds[index - 1] >= requestIds[index]) {
      throw new Error("Withdrawal request ids must be in ascending FIFO order");
    }
  }

  return requestIds;
};

module.exports = { parseRequestIds };
