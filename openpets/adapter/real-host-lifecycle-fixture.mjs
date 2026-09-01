import { mkdtemp, rm } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { ADAPTER_PORT, startAdapter } from "./tycho-loopback-adapter.mjs";

const directory = await mkdtemp(join(tmpdir(), "tycho-openpets-host-fixture-"));
let requestCount = 0;

function sourceAgent(key, status) {
  return { key, status, unread: false, archived: false, awaiting_input: false, blocked: status === "blocked" };
}

function sourceSnapshot(agents) {
  return {
    schema_version: 1,
    servers: [{ key: "synthetic-server", status: "online", stale: false, agents }],
  };
}

try {
  const running = await startAdapter({
    origin: "http://127.0.0.1:7373",
    credential: randomUUID(),
    stateFile: join(directory, "assignments.json"),
    port: ADAPTER_PORT,
    fetchImpl: async () => {
      requestCount += 1;
      const agents = requestCount <= 2
        ? [sourceAgent("alpha", "running"), sourceAgent("beta", "running")]
        : requestCount <= 4
          ? [sourceAgent("alpha", "partial"), sourceAgent("beta", "partial")]
          : [];
      return new Response(JSON.stringify(sourceSnapshot(agents)), { status: 200 });
    },
  });
  process.stdout.write("Synthetic real-host fixture ready: running -> partial -> release.\n");
  await new Promise((resolve) => setTimeout(resolve, 27_000));
  await running.close();
} finally {
  await rm(directory, { recursive: true, force: true });
}
