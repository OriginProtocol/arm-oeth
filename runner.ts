import { existsSync, readFileSync } from "node:fs";

import { type ActionsCatalog, runContainer } from "@oplabs/talos-client";

// The catalog is dumped at image build time by docker/dump-actions-catalog.cjs
// (Node, where hardhat works). Reading it here keeps the runner's bun parent
// out of hardhat's load path, which crashes under bun (keccak native module —
// bun#18546). Missing/invalid file ⇒ empty catalog ⇒ admin UI fail-closes
// to zero editable flags for this product.
const CATALOG_PATH = "/app/actions-catalog.json";
let actionsCatalog: ActionsCatalog = {};
if (existsSync(CATALOG_PATH)) {
  try {
    actionsCatalog = JSON.parse(readFileSync(CATALOG_PATH, "utf8"));
    console.log(
      `[runner] loaded actions catalog: ${Object.keys(actionsCatalog).length} tasks`,
    );
  } catch (err) {
    console.warn(
      `[runner] failed to parse ${CATALOG_PATH}: ${(err as Error).message}`,
    );
  }
}

await runContainer({
  product: "arm-oeth",
  baseUrl: process.env.RUNNER_BASE_URL ?? "http://arm-oeth:8080",
  workdir: "/app",
  actionsCatalog,
});
