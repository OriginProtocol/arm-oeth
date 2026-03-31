import { action } from "../lib/action";

action({
  name: "healthcheck",
  description: "Simple health check to verify the action system works",
  run: async ({ log, chainId, networkName }) => {
    log.info(`Health check passed on ${networkName} (${chainId})`);
  },
});
