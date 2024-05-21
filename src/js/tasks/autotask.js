const { AutotaskClient } = require("@openzeppelin/defender-autotask-client");

const setAutotaskVars = async (options) => {
  const creds = {
    apiKey: process.env.API_KEY,
    apiSecret: process.env.API_SECRET,
  };
  const client = new AutotaskClient(creds);

  // Update Variables
  const variables = await client.updateEnvironmentVariables(options.id, {
    DEBUG: "origin*",
  });
  console.log("updated Autotask environment variables", variables);
};

module.exports = {
  setAutotaskVars,
};
