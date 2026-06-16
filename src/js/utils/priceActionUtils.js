const legacyBaseMismatch = (error) =>
  error?.message?.startsWith("Legacy ") &&
  error.message.includes(" only supports ");

const runForBases = async ({ bases, options, actionName, fn }) => {
  const results = [];
  for (const base of bases) {
    try {
      console.log(`${actionName} for ${options.armName} ARM ${base}`);
      results.push(
        await fn({
          ...options,
          base,
        }),
      );
    } catch (error) {
      if (!legacyBaseMismatch(error)) throw error;
      console.log(`Skipping ${base}: ${error.message}`);
    }
  }
  return results;
};

const setPricesForBases = async ({ setPrices, bases, options }) =>
  runForBases({
    bases,
    options,
    actionName: "Setting prices",
    fn: (baseOptions) =>
      setPrices({
        ...options,
        base: baseOptions.base,
      }),
  });

module.exports = {
  runForBases,
  setPricesForBases,
};
