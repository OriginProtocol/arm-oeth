import { buildActionsCatalog, runContainer } from "@talos/client";
import hre from "hardhat";

const actionsCatalog = buildActionsCatalog(hre);

await runContainer({
  product: "arm-oeth",
  baseUrl: process.env.RUNNER_BASE_URL ?? "http://arm-oeth:8080",
  workdir: "/app",
  actionsCatalog,
});
