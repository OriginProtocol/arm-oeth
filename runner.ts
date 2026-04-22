import { runContainer } from "@talos/client";

await runContainer({
  product: "arm-oeth",
  baseUrl: process.env.RUNNER_BASE_URL ?? "http://arm-oeth:8080",
  workdir: "/app",
});
