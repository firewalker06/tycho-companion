import { performance } from "node:perf_hooks";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { createTestHarness } from "@open-pets/plugin-sdk/testing";
import { AssignmentStore, sanitizeActivity } from "./adapter/tycho-loopback-adapter.mjs";
import { ADAPTER_SNAPSHOT_URL, STORAGE_KEY, reconcileSnapshot, register } from "./plugin/index.js";

const count = 100;
const source = {
  schema_version: 1,
  servers: [{
    key: "synthetic-server",
    status: "online",
    stale: false,
    agents: Array.from({ length: count }, (_, index) => ({
      key: `synthetic-agent-${index}`,
      status: index % 10 === 0 ? "blocked" : index % 3 === 0 ? "running" : "idle",
      unread: index % 13 === 0,
      archived: false,
      awaiting_input: false,
      blocked: index % 10 === 0,
    })),
  }],
};

const directory = await mkdtemp(join(tmpdir(), "tycho-openpets-benchmark-"));
try {
  const store = new AssignmentStore(join(directory, "state.json"));
  await store.load();
  const adapterStartedAt = performance.now();
  let sanitized;
  for (let iteration = 0; iteration < 100; iteration += 1) sanitized = await sanitizeActivity(source, store);
  const adapterElapsedMs = performance.now() - adapterStartedAt;

  const permissions = ["network", "network:local", "schedule", "storage", "pet:speak", "pet:pin", "pet:reaction", "pets:manage", "commands", "status"];
  const harness = createTestHarness(register, { permissions, config: { petPackageIds: "snoopy" }, nowMs: 1_000_000 });
  harness.net.mock(ADAPTER_SNAPSHOT_URL, { json: sanitized });
  await harness.start();
  const pluginStartedAt = performance.now();
  for (let iteration = 0; iteration < 10_000; iteration += 1) await reconcileSnapshot(harness.ctx, sanitized);
  const pluginElapsedMs = performance.now() - pluginStartedAt;
  const persistedBytes = Buffer.byteLength(JSON.stringify(harness.calls.storage.get(STORAGE_KEY)));
  await harness.stop();

  process.stdout.write(`${JSON.stringify({
    adapter: {
      entities: count,
      iterations: 100,
      elapsed_ms: Number(adapterElapsedMs.toFixed(2)),
      average_ms: Number((adapterElapsedMs / 100).toFixed(3)),
    },
    plugin_unchanged_snapshot: {
      iterations: 10_000,
      elapsed_ms: Number(pluginElapsedMs.toFixed(2)),
      average_ms: Number((pluginElapsedMs / 10_000).toFixed(5)),
    },
    persisted_state_bytes: persistedBytes,
    process_rss_mib: Number((process.memoryUsage().rss / 1024 / 1024).toFixed(1)),
  }, null, 2)}\n`);
} finally {
  await rm(directory, { recursive: true, force: true });
}
