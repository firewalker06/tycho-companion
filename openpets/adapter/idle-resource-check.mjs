import { mkdtemp, rm } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { startAdapter } from "./tycho-loopback-adapter.mjs";

const directory = await mkdtemp(join(tmpdir(), "tycho-openpets-idle-check-"));
const credential = randomUUID();
const activity = JSON.stringify({
  schema_version: 1,
  servers: [{ key: "synthetic-server", status: "online", stale: false, agents: [] }],
});

try {
  const running = await startAdapter({
    origin: "http://127.0.0.1:7373",
    credential,
    stateFile: join(directory, "state.json"),
    port: process.env.TYCHO_OPENPETS_PORT ? Number(process.env.TYCHO_OPENPETS_PORT) : 0,
    fetchImpl: async () => new Response(activity, { status: 200 }),
  });
  const durationMs = process.env.TYCHO_OPENPETS_DURATION_MS ? Number(process.env.TYCHO_OPENPETS_DURATION_MS) : 5_000;
  await new Promise((resolve) => setTimeout(resolve, durationMs));
  await running.close();
} finally {
  await rm(directory, { recursive: true, force: true });
}
