import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  ADAPTER_HOST,
  AssignmentStore,
  PollController,
  TychoPoller,
  sanitizeActivity,
  startAdapter,
  transientBackoffMs,
  validateTychoOrigin,
} from "../tycho-loopback-adapter.mjs";

function agent(key, status = "idle", extra = {}) {
  return { key, status, unread: false, archived: false, awaiting_input: false, blocked: false, ...extra };
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

test("current Tycho server status contract maps loading and unauthorized to attention", async (t) => {
  const { store } = await temporaryStore(t);
  const loading = await sanitizeActivity(activity([server("loading", [agent("a", "running")], { status: "loading" })]), store);
  assert.equal(loading.health, "stale");
  assert.equal(loading.pets[0].health, "stale");
  assert.equal(loading.pets[0].attention, true);
  assert.equal(loading.pets[0].lifecycle, "running");

  const unauthorized = await sanitizeActivity(activity([server("loading", [agent("a", "running")], { status: "unauthorized" })]), store);
  assert.equal(unauthorized.health, "offline");
  assert.equal(unauthorized.pets[0].health, "offline");
  assert.equal(unauthorized.pets[0].attention, true);
  assert.equal(unauthorized.pets[0].lifecycle, "running");
});

test("malformed server or agent rows reject atomically and preserve assignments", async (t) => {
  const { store } = await temporaryStore(t);
  const valid = activity([server("s", [agent("a", "running")])]);
  const first = await sanitizeActivity(valid, store);
  const assignments = [...store.assignments];
  const malformed = [
    activity([server("s", [agent("a", "running")]), { key: "bad", status: "mystery", stale: false, agents: [] }]),
    activity([server("s", [agent("a", "unknown")])]),
    activity([server("s", [{ ...agent("a"), unread: "yes" }])]),
    activity([server("s", [agent("a")]), null]),
    activity([server("s", [agent("a"), agent("a")])]),
    activity([server("s", []), server("s", [])]),
  ];
  for (const candidate of malformed) {
    await assert.rejects(sanitizeActivity(candidate, store));
    assert.deepEqual([...store.assignments], assignments);
  }
  assert.deepEqual(await sanitizeActivity(valid, store), first);
});

test("malformed successful responses preserve state and assignments but mark the snapshot stale", async (t) => {
  const invalidResponses = [
    () => new Response(JSON.stringify(activity([server("s", [agent("a", "invented")])])), { status: 200 }),
    () => new Response(JSON.stringify({ schema_version: 99, servers: [] }), { status: 200 }),
    () => new Response("not-json", { status: 200 }),
    () => new Response("{}", { status: 200, headers: { "content-length": String(600 * 1024) } }),
  ];
  for (const invalidResponse of invalidResponses) {
    const { store } = await temporaryStore(t);
    const responses = [
      new Response(JSON.stringify(activity([server("s", [agent("a", "running", { unread: true })])])), { status: 200 }),
      invalidResponse(),
    ];
    const poller = new TychoPoller({
      origin: "http://127.0.0.1:7373",
      credential: randomUUID(),
      store,
      fetchImpl: async () => responses.shift(),
    });
    const valid = await poller.poll();
    const assignments = [...store.assignments];
    const degraded = await poller.poll();
    assert.notEqual(degraded.revision, valid.revision);
    assert.equal(degraded.health, "stale");
    assert.equal(degraded.pets[0].health, "stale");
    assert.equal(degraded.pets[0].lifecycle, "running");
    assert.equal(degraded.pets[0].unread, true);
    assert.equal(degraded.pets[0].attention, true);
    assert.deepEqual([...store.assignments], assignments);
    assert.equal(poller.outcome, "transient");
  }
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

test("one confirmed 401 halts polling until explicit safe reconfiguration", async (t) => {
  const { store } = await temporaryStore(t);
  let calls = 0;
  const poller = new TychoPoller({
    origin: "http://127.0.0.1:7373",
    credential: randomUUID(),
    store,
    fetchImpl: async () => {
      calls += 1;
      return calls === 1
        ? new Response("denied", { status: 401 })
        : new Response(JSON.stringify(activity([])), { status: 200 });
    },
  });
  const scheduled = [];
  const controller = new PollController({ poller, schedule: (_callback, delay) => scheduled.push(delay), cancel: () => {} });
  await controller.start();
  assert.equal(calls, 1);
  assert.equal(poller.authenticationBlocked, true);
  assert.deepEqual(scheduled, []);
  await controller.tick();
  assert.equal(calls, 1);
  await controller.reconfigure({ origin: "http://localhost:7373", credential: randomUUID() });
  assert.equal(calls, 2);
  assert.equal(poller.authenticationBlocked, false);
  assert.deepEqual(scheduled, [5_000]);
  controller.stop();
});

test("transient retry delays are deterministic exponential and bounded", async (t) => {
  assert.deepEqual([1, 2, 3, 4, 5, 20].map(transientBackoffMs), [5_000, 10_000, 20_000, 40_000, 60_000, 60_000]);
  const { store } = await temporaryStore(t);
  const poller = new TychoPoller({
    origin: "http://127.0.0.1:7373",
    credential: randomUUID(),
    store,
    fetchImpl: async () => new Response("unavailable", { status: 503 }),
  });
  const scheduled = [];
  const callbacks = [];
  const controller = new PollController({
    poller,
    schedule: (callback, delay) => { callbacks.push(callback); scheduled.push(delay); return callbacks.length; },
    cancel: () => {},
  });
  await controller.start();
  await callbacks.shift()();
  await callbacks.shift()();
  await callbacks.shift()();
  await callbacks.shift()();
  assert.deepEqual(scheduled, [5_000, 10_000, 20_000, 40_000, 60_000]);
  controller.stop();
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

test("loopback serves a bounded stale snapshot after a malformed successful Tycho response", async (t) => {
  const { filePath } = await temporaryStore(t);
  const responses = [
    new Response(JSON.stringify(activity([server("s", [agent("a", "running")])])), { status: 200 }),
    new Response("not-json", { status: 200 }),
  ];
  const running = await startAdapter({
    origin: "http://localhost:7373",
    credential: randomUUID(),
    stateFile: filePath,
    port: 0,
    fetchImpl: async () => responses.shift(),
  });
  t.after(() => running.close());
  const assignments = [...running.poller.store.assignments];
  await running.poller.poll();
  const response = await fetch(`http://${ADAPTER_HOST}:${running.address.port}/snapshot`);
  const served = await response.json();
  assert.equal(served.health, "stale");
  assert.equal(served.pets[0].health, "stale");
  assert.equal(served.pets[0].lifecycle, "running");
  assert.equal(served.pets[0].attention, true);
  assert.deepEqual([...running.poller.store.assignments], assignments);
  assert.ok(JSON.stringify(served).length < 2_000);
});
