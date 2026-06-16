import { action } from "../lib/action";

action({
  name: "healthcheck",
  description: "Simple health check to verify the action system works",
  run: async ({ signer, log }) => {
    log.info(`Health check passed. Signer: ${await signer.getAddress()}`);
  },
});
