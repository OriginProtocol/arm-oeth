const { AutotaskClient } = require("@openzeppelin/defender-autotask-client");
const path = require("path");

require("dotenv").config({ path: path.resolve(__dirname, "../../../.env") });

const log = require("../utils/logger")("task:defender");

const setActionVars = async (options) => {
  log(`Used DEFENDER_TEAM_KEY ${process.env.DEFENDER_TEAM_KEY}`);
  const creds = {
    apiKey: process.env.DEFENDER_TEAM_KEY,
    apiSecret: process.env.DEFENDER_TEAM_SECRET,
  };
  const client = new AutotaskClient(creds);

  // Update Variables
  const variables = await client.updateEnvironmentVariables(options.id, {
    DEBUG: "origin*",
  });
  console.log("updated Autotask environment variables", variables);
};

module.exports = {
  setActionVars,
};
