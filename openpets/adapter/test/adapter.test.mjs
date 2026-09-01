import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  ADAPTER_HOST,
  AssignmentStore,
  TychoPoller,
  sanitizeActivity,
  startAdapter,
  validateTychoOrigin,
} from "../tycho-loopback-adapter.mjs";

function agent(key, status = "idle", extra = {}) {
  return { key, status, unread: false, archived: false, ...extra };
}

function activity(servers) {
  return { schema_version: 1, revision: "source-revision-is-not-forwarded", servers };
}

function server(key, agents, extra = {}) {
  return { key, status: "online", stale: false, agents, ...extra };
}

async function temporaryStore(t) {
  const directory = await mkdtemp(join(tmpdir(), "tycho-openpets-adapter-test-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const filePath = join(directory, "state.json");
  const store = new AssignmentStore(filePath);
  await store.load();
  return { store, filePath };
}

test("origin validation accepts only the Tycho allowlist", () => {
  for (const value of ["http://127.0.0.1:7373", "http://localhost", "https://tycho", "https://tycho.example.ts.net"]) {
    assert.ok(validateTychoOrigin(value), value);
  }
  for (const value of ["http://127.0.0.2", "https://example.com", "https://user@tycho", "https://tycho/path", "ftp://localhost"]) {
    assert.equal(validateTychoOrigin(value), null, value);
  }
});

test("sanitization keeps lifecycle and unread independent with opaque stable identities", async (t) => {
  const { store, filePath } = await temporaryStore(t);
  const first = await sanitizeActivity(activity([
    server("one", [
      agent("run", "running"),
      agent("wait", "running", { awaiting_input: true, unread: true }),
      agent("block", "running", { blocked: true }),
      agent("done", "succeeded", { unread: true }),
    ]),
    server("two", [agent("run", "failed")], { stale: true }),
  ]), store);

  assert.equal(first.pets.length, 5);
  assert.deepEqual(first.counts, { total: 5, active: 1, attention: 4, unread: 2 });
  assert.equal(first.health, "stale");
  assert.equal(first.pets.find((pet) => pet.lifecycle === "awaiting-input").unread, true);
  assert.equal(first.pets.find((pet) => pet.lifecycle === "awaiting-input").active, false);
  assert.equal(first.pets.find((pet) => pet.lifecycle === "blocked").attention, true);
  assert.equal(first.pets.find((pet) => pet.lifecycle === "failed").health, "stale");
  assert.ok(first.pets.every((pet) => /^[a-f0-9-]{36}$/.test(pet.entity_id)));
  assert.equal(new Set(first.pets.map((pet) => pet.entity_id)).size, 5, "server identity must qualify duplicate agent keys");
  assert.deepEqual(Object.keys(first.pets[0]).sort(), ["active", "attention", "entity_id", "health", "lifecycle", "unread"]);

  const reloaded = new AssignmentStore(filePath);
  await reloaded.load();
  const second = await sanitizeActivity(activity([
    server("one", [agent("run", "running"), agent("wait", "running", { awaiting_input: true, unread: true }), agent("block", "running", { blocked: true }), agent("done", "succeeded", { unread: true })]),
    server("two", [agent("run", "failed")], { stale: true }),
  ]), reloaded);
  assert.deepEqual(second, first, "restart and repeated source snapshots must be stable");
  assert.equal((await stat(filePath)).mode & 0o777, 0o600);
  const persisted = JSON.parse(await readFile(filePath, "utf8"));
  assert.ok(Object.keys(persisted.assignments).every((key) => /^[a-f0-9]{64}$/.test(key)));
  assert.ok(!JSON.stringify(persisted).includes("one"));
  assert.ok(!JSON.stringify(persisted).includes("run"));
});

test("terminal, stale, rerun, archive, and cleanup have stable release semantics", async (t) => {
  const { store } = await temporaryStore(t);
  const terminal = await sanitizeActivity(activity([server("s", [agent("a", "succeeded")])]), store);
  const entityId = terminal.pets[0].entity_id;
  const rerun = await sanitizeActivity(activity([server("s", [agent("a", "running")])]), store);
  assert.equal(rerun.pets[0].entity_id, entityId);
  const stale = await sanitizeActivity(activity([server("s", [agent("a", "running")], { stale: true })]), store);
  assert.equal(stale.pets[0].entity_id, entityId);
  assert.equal(stale.pets[0].health, "stale");
  const archived = await sanitizeActivity(activity([server("s", [agent("a", "stopped", { archived: true })])]), store);
  assert.equal(archived.pets.length, 0);
  assert.equal(store.assignments.size, 0);
  const recreated = await sanitizeActivity(activity([server("s", [agent("a", "running")])]), store);
  assert.notEqual(recreated.pets[0].entity_id, entityId, "an archived assignment must be released");
});

test("poll failures preserve the last valid snapshot as offline without changing lifecycle or unread", async (t) => {
  const { store } = await temporaryStore(t);
  const responses = [
    new Response(JSON.stringify(activity([server("s", [agent("a", "failed", { unread: true })])])), { status: 200 }),
    new Response("unavailable", { status: 503 }),
  ];
  const calls = [];
  const credential = randomUUID();
  const poller = new TychoPoller({
    origin: "http://127.0.0.1:7373",
    credential,
    store,
    fetchImpl: async (url, options) => {
      calls.push({ url, method: options.method, authorization: options.headers.Authorization });
      return responses.shift();
    },
  });
  const live = await poller.poll();
  const offline = await poller.poll();
  assert.equal(live.pets[0].lifecycle, "failed");
  assert.equal(offline.pets[0].lifecycle, "failed");
  assert.equal(offline.pets[0].unread, true);
  assert.equal(offline.pets[0].health, "offline");
  assert.ok(offline.pets[0].attention);
  assert.deepEqual(calls.map((call) => [new URL(call.url).pathname, call.method]), [["/servers/activity", "GET"], ["/servers/activity", "GET"]]);
  assert.ok(calls.every((call) => call.authorization === `Bearer ${credential}`));
  assert.ok(!JSON.stringify(offline).includes(credential));
});

test("unsupported schema, invalid JSON, authorization failure, oversize, and timeout fail closed", async (t) => {
  const { store } = await temporaryStore(t);
  const cases = [
    async () => new Response(JSON.stringify({ schema_version: 99, servers: [] }), { status: 200 }),
    async () => new Response("not-json", { status: 200 }),
    async () => new Response("denied", { status: 401 }),
    async () => new Response("{}", { status: 200, headers: { "content-length": String(600 * 1024) } }),
    async (_url, options) => new Promise((resolve, reject) => {
      options.signal.addEventListener("abort", () => reject(new Error("aborted")), { once: true });
    }),
  ];
  for (const fetchImpl of cases) {
    const poller = new TychoPoller({
      origin: "http://127.0.0.1:7373",
      credential: randomUUID(),
      store,
      fetchImpl,
      timeoutMs: 5,
    });
    const result = await poller.poll();
    assert.equal(result.health, "offline");
    assert.deepEqual(result.pets, []);
  }
  const empty = new TychoPoller({
    origin: "http://127.0.0.1:7373",
    credential: randomUUID(),
    store,
    fetchImpl: async () => new Response(JSON.stringify(activity([])), { status: 200 }),
  });
  assert.equal((await empty.poll()).health, "online");
});

test("loopback server exposes only GET /snapshot and never returns its credential", async (t) => {
  const { filePath } = await temporaryStore(t);
  const credential = randomUUID();
  const running = await startAdapter({
    origin: "http://localhost:7373",
    credential,
    stateFile: filePath,
    port: 0,
    fetchImpl: async () => new Response(JSON.stringify(activity([server("s", [agent("a", "running")])])), { status: 200 }),
  });
  t.after(() => running.close());
  assert.equal(running.address.address, ADAPTER_HOST);
  const base = `http://${ADAPTER_HOST}:${running.address.port}`;
  const response = await fetch(`${base}/snapshot`);
  const body = await response.text();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.ok(!body.includes(credential));
  assert.equal((await fetch(`${base}/snapshot`, { method: "POST" })).status, 405);
  assert.equal((await fetch(`${base}/other`)).status, 404);
});
