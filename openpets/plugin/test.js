import assert from "node:assert/strict";
import test from "node:test";
import { createTestHarness } from "@open-pets/plugin-sdk/testing";

import {
  ADAPTER_SNAPSHOT_URL,
  MAX_VISIBLE_PETS,
  POLL_SCHEDULE_ID,
  STORAGE_KEY,
  register,
  transientPollDelay,
  validateSnapshot,
  visibilityPriority,
} from "./index.js";

const PERMISSIONS = [
  "network",
  "network:local",
  "schedule",
  "storage",
  "pet:speak",
  "pet:pin",
  "pet:reaction",
  "pets:manage",
  "commands",
  "status",
];

function entity(index, lifecycle = "idle", extra = {}) {
  return {
    entity_id: `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
    lifecycle,
    active: lifecycle === "running",
    attention: ["awaiting-input", "blocked", "succeeded", "failed", "partial", "stopped"].includes(lifecycle),
    unread: false,
    health: "online",
    ...extra,
  };
}

function snapshot(revision, pets, health = "online") {
  return { schema_version: 1, revision, health, pets };
}

function harnessFor(value, config = { petPackageIds: "snoopy" }) {
  const harness = createTestHarness(register, { permissions: PERMISSIONS, config, nowMs: 1_000_000 });
  harness.net.mock(ADAPTER_SNAPSHOT_URL, { json: value });
  return harness;
}

test("snapshot validation rejects unbounded or identity-bearing shapes", () => {
  assert.ok(validateSnapshot(snapshot("r1", [entity(1, "running")])));
  assert.equal(validateSnapshot({ ...snapshot("r1", [entity(1)]), pets: [{ ...entity(1), entity_id: "server/agent" }] }), null);
  assert.equal(validateSnapshot(snapshot("r1", [entity(1), entity(1)])), null);
  assert.equal(validateSnapshot(snapshot("r1", [{ ...entity(1), lifecycle: "unknown" }])), null);
  assert.ok(visibilityPriority(entity(1, "blocked")) > visibilityPriority(entity(2, "running")));
  assert.ok(visibilityPriority(entity(1, "idle", { unread: true })) > visibilityPriority(entity(2, "failed")));
  assert.deepEqual([5_000, 10_000, 20_000, 40_000, 60_000].map(transientPollDelay), [10_000, 20_000, 40_000, 60_000, 60_000]);
});

test("the default pet plus four same-package spawns enforce five visible pets and explicit overflow", async () => {
  const h = harnessFor(snapshot("r1", Array.from({ length: 7 }, (_, index) => entity(index + 1, "running"))));
  const handles = [];
  const spawn = h.ctx.pets.spawn;
  h.ctx.pets.spawn = async (spec) => {
    const handle = await spawn(spec);
    handles.push(handle.id);
    return handle;
  };
  await h.start();
  assert.equal(MAX_VISIBLE_PETS, 5);
  assert.deepEqual(h.calls.spawnedPets, ["snoopy", "snoopy", "snoopy", "snoopy"]);
  assert.equal(new Set(handles).size, 4, "same-package spawns must still be distinct pet instances");
  assert.match(h.calls.status.at(-1).text, /5\/7 visible/);
  assert.match(h.calls.status.at(-1).text, /\+2 overflow/);
  h.expectScheduled(POLL_SCHEDULE_ID);
  h.expectNetCall("/snapshot");
  await h.stop();
});

test("a unique package pool assigns distinct pet IDs without changing the host", async () => {
  const h = harnessFor(
    snapshot("r1", Array.from({ length: 5 }, (_, index) => entity(index + 1, "idle"))),
    { petPackageIds: "snoopy,tux,wall-e,clippit" },
  );
  await h.start();
  assert.deepEqual(h.calls.spawnedPets, ["tux", "wall-e", "clippit", "snoopy"]);
  assert.equal(new Set(h.calls.spawnedPets).size, 4);
  await h.stop();
});

test("spawn, update, terminal, unread, rerun, stale, and archive reconcile without replay", async () => {
  const running = snapshot("r1", [entity(1, "running"), entity(2, "idle")]);
  const h = harnessFor(running);
  let closes = 0;
  const spawn = h.ctx.pets.spawn;
  h.ctx.pets.spawn = async (spec) => {
    const handle = await spawn(spec);
    return { ...handle, close: async () => { closes += 1; await handle.close(); } };
  };
  await h.start();
  assert.equal(h.calls.spawnedPets.length, 1);
  const initialReactions = h.calls.react.length;

  const terminalUnread = snapshot("r2", [entity(1, "succeeded", { unread: true, attention: true }), entity(2, "idle")]);
  h.net.mock(ADAPTER_SNAPSHOT_URL, { json: terminalUnread });
  await h.clock.advance("5s");
  assert.equal(h.calls.spawnedPets.length, 1, "updating an assigned entity must not respawn it");
  assert.equal(h.calls.react.length, initialReactions + 1);
  assert.equal(h.calls.react.at(-1), "success");
  assert.ok(h.calls.bubbles.some((bubble) => bubble.spec.text === "Succeeded · unread"));

  await h.clock.advance("5s");
  assert.equal(h.calls.react.length, initialReactions + 1, "repeated snapshots must not replay terminal or unread reactions");

  const rerun = snapshot("r3", [entity(1, "running", { unread: true, attention: true }), entity(2, "idle")]);
  h.net.mock(ADAPTER_SNAPSHOT_URL, { json: rerun });
  await h.clock.advance("5s");
  assert.equal(h.calls.spawnedPets.length, 1);

  const stale = snapshot("r4", [entity(1, "running", { unread: true, attention: true, health: "stale" }), entity(2, "idle", { health: "stale", attention: true })], "stale");
  h.net.mock(ADAPTER_SNAPSHOT_URL, { json: stale });
  await h.clock.advance("5s");
  assert.ok(h.calls.bubbles.some((bubble) => bubble.spec.text === "Data stale · unread"));
  assert.equal(h.calls.spawnedPets.length, 1);

  h.net.mock(ADAPTER_SNAPSHOT_URL, { json: snapshot("r5", [entity(2, "idle")]) });
  await h.clock.advance("5s");
  assert.equal(closes, 0, "the archived entity occupied the default pet, so no spawned window closes yet");
  assert.equal(h.calls.spawnedPets.length, 1, "the retained entity keeps its stable non-default slot");
  await h.stop();
  assert.equal(closes, 1, "cleanup closes the retained spawned instance");
});

test("attention states stay recognizable while lifecycle and unread remain independent", async () => {
  const h = harnessFor(snapshot("states", [
    entity(1, "running"),
    entity(2, "awaiting-input"),
    entity(3, "blocked"),
    entity(4, "failed", { unread: true }),
    entity(5, "stopped"),
  ]));
  await h.start();
  const texts = h.calls.bubbles.map((bubble) => bubble.spec.text).filter(Boolean);
  assert.ok(texts.includes("Input needed"));
  assert.ok(texts.includes("Blocked"));
  assert.ok(texts.includes("Failed · unread"));
  assert.ok(texts.includes("Stopped"));
  assert.ok(h.calls.statusReactions.includes("working"));
  assert.ok(h.calls.statusReactions.includes("waiting"));
  assert.ok(h.calls.statusReactions.includes("error"));
  assert.match(h.calls.status.at(-1).text, /4 attention/);
  assert.match(h.calls.status.at(-1).text, /1 unread/);
  await h.stop();
});

test("partial has a persistent waiting cue, label, and one transition reaction", async () => {
  const h = harnessFor(snapshot("partial-1", [entity(1, "running")]));
  await h.start();
  const reactions = h.calls.react.length;
  h.net.mock(ADAPTER_SNAPSHOT_URL, { json: snapshot("partial-2", [entity(1, "partial")]) });
  await h.clock.advance("5s");
  assert.equal(h.calls.statusReactions.at(-1), "waiting");
  assert.ok(h.calls.bubbles.some((bubble) => bubble.spec.text === "Partial"));
  assert.equal(h.calls.react.length, reactions + 1);
  assert.equal(h.calls.react.at(-1), "waiting");
  await h.clock.advance("5s");
  assert.equal(h.calls.react.length, reactions + 1, "unchanged partial state must not replay");
  await h.stop();
});

test("server-wide offline state remains explicit even when there are no assigned pets", async () => {
  const h = harnessFor(snapshot("offline-empty", [], "offline"));
  await h.start();
  assert.match(h.calls.status.at(-1).text, /Tycho offline/);
  assert.equal(h.calls.status.at(-1).tone, "warning");
  assert.equal(h.calls.spawnedPets.length, 0);
  await h.stop();
});

test("adapter restart and plugin restart rehydrate assignments but do not replay transitions", async () => {
  const value = snapshot("stable", [entity(1, "succeeded", { unread: true, attention: true }), entity(2, "running")]);
  const first = harnessFor(value);
  await first.start();
  assert.equal(first.calls.react.length, 0, "initial terminal state is rendered without a one-shot replay");
  const persisted = structuredClone(first.calls.storage.get(STORAGE_KEY));
  assert.deepEqual(Object.keys(persisted).sort(), ["assignment_revision", "assignments"]);
  assert.equal(persisted.assignment_revision, 1);
  for (const forbidden of ["lifecycle", "active", "attention", "unread", "health", "revision"]) {
    assert.equal(JSON.stringify(persisted).includes(`\"${forbidden}\"`), false, `${forbidden} must remain memory-only`);
  }
  const firstPackages = [...first.calls.spawnedPets];
  await first.stop();

  const restarted = harnessFor(value);
  restarted.calls.storage.set(STORAGE_KEY, persisted);
  await restarted.start();
  assert.deepEqual(restarted.calls.spawnedPets, firstPackages);
  assert.equal(restarted.calls.react.length, 0, "plugin restart must not replay terminal or unread transitions");
  assert.deepEqual(restarted.calls.storage.get(STORAGE_KEY).assignments, persisted.assignments);
  await restarted.stop();
});

test("legacy assignment storage migrates without retaining activity history", async () => {
  const value = snapshot("current", [entity(1, "succeeded", { unread: true, attention: true })]);
  const h = harnessFor(value);
  h.calls.storage.set(STORAGE_KEY, {
    version: 1,
    revision: "legacy-source-revision",
    assignments: { [entity(1).entity_id]: { petId: "snoopy", slot: 0 } },
    last: { [entity(1).entity_id]: entity(1, "failed", { unread: true, attention: true }) },
  });
  await h.start();
  assert.deepEqual(Object.keys(h.calls.storage.get(STORAGE_KEY)).sort(), ["assignment_revision", "assignments"]);
  assert.equal(h.calls.react.length, 0, "discarded legacy history cannot replay a transition");
  await h.stop();
});

test("a malformed adapter snapshot preserves the last valid model and assignments", async () => {
  const h = harnessFor(snapshot("valid", [entity(1, "running"), entity(2, "idle")]));
  await h.start();
  const persisted = structuredClone(h.calls.storage.get(STORAGE_KEY));
  const reactions = [...h.calls.statusReactions];
  const bubbleCount = h.calls.bubbles.length;
  h.net.mock(ADAPTER_SNAPSHOT_URL, { json: snapshot("bad", [{ ...entity(3), lifecycle: "invented" }]) });
  await h.clock.advance("5s");
  assert.deepEqual(h.calls.storage.get(STORAGE_KEY), persisted);
  assert.deepEqual(h.calls.statusReactions, reactions);
  assert.equal(h.calls.bubbles.length, bubbleCount);
  assert.match(h.calls.status.at(-1).text, /response rejected/);
  await h.stop();
});

test("unload during a delayed fetch cannot write, spawn, or reschedule after cleanup", async () => {
  const h = createTestHarness(register, { permissions: PERMISSIONS, config: { petPackageIds: "snoopy" }, nowMs: 1_000_000 });
  let releaseFetch;
  let markFetchStarted;
  const fetchStarted = new Promise((resolve) => { markFetchStarted = resolve; });
  const delayed = new Promise((resolve) => { releaseFetch = resolve; });
  h.ctx.net.fetch = async () => {
    markFetchStarted();
    await delayed;
    return { ok: true, json: snapshot("late", [entity(1, "running"), entity(2, "blocked")]) };
  };
  const starting = h.start();
  await fetchStarted;
  await h.stop();
  const statusCount = h.calls.status.length;
  releaseFetch();
  await starting;
  assert.equal(h.calls.storage.has(STORAGE_KEY), false);
  assert.equal(h.calls.spawnedPets.length, 0);
  assert.equal(h.calls.status.length, statusCount);
  assert.equal(h.calls.schedules.size, 0);
  assert.equal(h.calls.commands.size, 0);
});

test("network loss keeps the last sanitized model, marks it offline once, backs off, and cleans up", async () => {
  const h = harnessFor(snapshot("r1", [entity(1, "running"), entity(2, "idle")]));
  let closes = 0;
  const spawn = h.ctx.pets.spawn;
  h.ctx.pets.spawn = async (spec) => {
    const handle = await spawn(spec);
    return { ...handle, close: async () => { closes += 1; await handle.close(); } };
  };
  await h.start();
  h.net.mock(ADAPTER_SNAPSHOT_URL, { status: 503, text: "" });
  await h.clock.advance("5s");
  const offlineBubbleCount = h.calls.bubbles.filter((bubble) => bubble.spec.text === "Tycho offline").length;
  assert.ok(offlineBubbleCount > 0);
  const reactionCount = h.calls.react.length;
  await h.clock.advance("10s");
  assert.equal(h.calls.react.length, reactionCount, "an unchanged outage must not replay attention reactions");
  assert.equal(h.calls.bubbles.filter((bubble) => bubble.spec.text === "Tycho offline").length, offlineBubbleCount);
  await h.stop();
  assert.equal(closes, 1);
  assert.equal(h.calls.schedules.size, 0);
  assert.equal(h.calls.commands.size, 0);
  assert.ok(h.calls.bubbles.every((bubble) => bubble.dismissed));
  assert.equal(h.calls.statusReactions.at(-1), null);
});
