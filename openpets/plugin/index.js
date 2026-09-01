/// <reference types="@open-pets/plugin-sdk" />

export const ADAPTER_SNAPSHOT_URL = "http://127.0.0.1:7737/snapshot";
export const POLL_SCHEDULE_ID = "tycho-companion-poll";
export const STORAGE_KEY = "sanitized-assignments-v1";
export const MAX_VISIBLE_PETS = 5;
export const MAX_SPAWNED_PETS = 4;

const LIFECYCLES = new Set([
  "idle",
  "running",
  "awaiting-input",
  "blocked",
  "succeeded",
  "failed",
  "partial",
  "stopped",
]);
const HEALTH = new Set(["online", "stale", "offline"]);
const TERMINAL = new Set(["succeeded", "failed", "partial", "stopped"]);
const POLL_MS = 5_000;
const MAX_BACKOFF_MS = 60_000;

let runtime = null;

function emptyState() {
  return { version: 1, revision: "", assignments: {}, last: {} };
}

function cleanState(value) {
  const state = emptyState();
  if (value?.version !== 1) return state;
  if (typeof value.revision === "string" && value.revision.length <= 128) state.revision = value.revision;
  if (value.assignments && typeof value.assignments === "object" && !Array.isArray(value.assignments)) {
    for (const [id, assignment] of Object.entries(value.assignments)) {
      if (!validEntityId(id) || !assignment || typeof assignment !== "object") continue;
      const petId = validPetPackageId(assignment.petId) ? assignment.petId : "snoopy";
      const slot = Number.isInteger(assignment.slot) && assignment.slot >= 0 && assignment.slot < MAX_VISIBLE_PETS ? assignment.slot : null;
      state.assignments[id] = { petId, slot };
    }
  }
  if (value.last && typeof value.last === "object" && !Array.isArray(value.last)) {
    for (const [id, entity] of Object.entries(value.last)) {
      const cleaned = cleanEntity(entity);
      if (validEntityId(id) && cleaned) state.last[id] = cleaned;
    }
  }
  return state;
}

function validEntityId(value) {
  return typeof value === "string" && /^[a-f0-9-]{36}$/.test(value);
}

function validPetPackageId(value) {
  return typeof value === "string" && /^[a-z0-9][a-z0-9._-]{0,63}$/.test(value);
}

function cleanEntity(value) {
  if (!value || typeof value !== "object" || !validEntityId(value.entity_id)) return null;
  if (!LIFECYCLES.has(value.lifecycle) || !HEALTH.has(value.health)) return null;
  if (typeof value.active !== "boolean" || typeof value.attention !== "boolean" || typeof value.unread !== "boolean") return null;
  return {
    entity_id: value.entity_id,
    lifecycle: value.lifecycle,
    active: value.active,
    attention: value.attention,
    unread: value.unread,
    health: value.health,
  };
}

export function validateSnapshot(value) {
  if (value?.schema_version !== 1 || typeof value.revision !== "string" || value.revision.length === 0 || value.revision.length > 128) return null;
  if (!HEALTH.has(value.health) || !Array.isArray(value.pets) || value.pets.length > 200) return null;
  const pets = [];
  const ids = new Set();
  for (const candidate of value.pets) {
    const entity = cleanEntity(candidate);
    if (!entity || ids.has(entity.entity_id)) return null;
    ids.add(entity.entity_id);
    pets.push(entity);
  }
  return { schema_version: 1, revision: value.revision, health: value.health, pets };
}

function packageIds(config) {
  const input = typeof config?.petPackageIds === "string" ? config.petPackageIds : "snoopy";
  const ids = input.split(",").map((value) => value.trim()).filter(validPetPackageId).slice(0, MAX_VISIBLE_PETS);
  return ids.length > 0 ? ids : ["snoopy"];
}

export function visibilityPriority(entity) {
  if (entity.health === "offline") return 900;
  if (entity.health === "stale") return 800;
  if (entity.lifecycle === "blocked") return 700;
  if (entity.lifecycle === "awaiting-input") return 650;
  if (entity.unread) return 600;
  if (entity.lifecycle === "failed") return 550;
  if (entity.lifecycle === "partial") return 500;
  if (entity.lifecycle === "stopped") return 450;
  if (entity.lifecycle === "succeeded") return 400;
  if (entity.lifecycle === "running") return 300;
  return 100;
}

function stateSignature(entity) {
  return `${entity.lifecycle}/${entity.health}/${entity.unread}`;
}

function statusReaction(entity) {
  if (entity.health !== "online") return null;
  return {
    running: "working",
    "awaiting-input": "waiting",
    blocked: "error",
    failed: "error",
    partial: "waiting",
  }[entity.lifecycle] ?? null;
}

function lifecycleLabel(lifecycle) {
  return {
    "awaiting-input": "Input needed",
    blocked: "Blocked",
    succeeded: "Succeeded",
    failed: "Failed",
    partial: "Partial",
    stopped: "Stopped",
  }[lifecycle] ?? "";
}

function bubbleText(entity) {
  let label = entity.health === "offline" ? "Tycho offline" : entity.health === "stale" ? "Data stale" : lifecycleLabel(entity.lifecycle);
  if (entity.unread) label = label ? `${label} · unread` : "Unread";
  return label;
}

function selectedEntities(pets) {
  return [...pets]
    .sort((left, right) => visibilityPriority(right) - visibilityPriority(left) || left.entity_id.localeCompare(right.entity_id))
    .slice(0, MAX_VISIBLE_PETS);
}

function assignSlots(state, selected) {
  const selectedIds = new Set(selected.map((entity) => entity.entity_id));
  const used = new Set();
  for (const id of selectedIds) {
    const slot = state.assignments[id]?.slot;
    if (Number.isInteger(slot) && !used.has(slot)) used.add(slot);
    else if (state.assignments[id]) state.assignments[id].slot = null;
  }
  for (const entity of selected) {
    if (state.assignments[entity.entity_id].slot !== null) continue;
    for (let slot = 0; slot < MAX_VISIBLE_PETS; slot += 1) {
      if (!used.has(slot)) {
        state.assignments[entity.entity_id].slot = slot;
        used.add(slot);
        break;
      }
    }
  }
  for (const [id, assignment] of Object.entries(state.assignments)) {
    if (!selectedIds.has(id)) assignment.slot = null;
  }
}

async function dismissBubble(id) {
  const bubble = runtime.bubbles.get(id);
  if (!bubble) return;
  runtime.bubbles.delete(id);
  try { await bubble.dismiss(); } catch {}
}

async function releasePet(id) {
  await dismissBubble(id);
  const entry = runtime.handles.get(id);
  if (!entry) return;
  runtime.handles.delete(id);
  try { await entry.handle.setStatusReaction(null); } catch {}
  if (entry.spawned) {
    try { await entry.handle.close(); } catch {}
  }
}

async function ensurePet(ctx, id, assignment) {
  const current = runtime.handles.get(id);
  if (current?.slot === assignment.slot && (!current.spawned || current.petId === assignment.petId)) return current.handle;
  if (current) await releasePet(id);
  if (assignment.slot === 0) {
    runtime.handles.set(id, { handle: ctx.pets.default, spawned: false, slot: 0, petId: "default" });
    return ctx.pets.default;
  }
  const handle = await ctx.pets.spawn({
    petId: assignment.petId,
    name: `Tycho pet ${assignment.slot + 1}`,
    ephemeral: true,
  });
  runtime.handles.set(id, { handle, spawned: true, slot: assignment.slot, petId: assignment.petId });
  return handle;
}

async function updateBubble(id, handle, entity) {
  const text = bubbleText(entity);
  const existing = runtime.bubbles.get(id);
  if (!text) {
    await dismissBubble(id);
    return;
  }
  const spec = { text, sticky: true, pin: true, dismissOn: [], priority: entity.attention ? "high" : "normal" };
  if (existing) {
    try {
      await existing.update(spec);
      return;
    } catch {
      runtime.bubbles.delete(id);
    }
  }
  runtime.bubbles.set(id, await handle.speak(spec));
}

async function renderEntity(ctx, entity, previous, force) {
  const assignment = runtime.state.assignments[entity.entity_id];
  let handle;
  try {
    handle = await ensurePet(ctx, entity.entity_id, assignment);
  } catch {
    runtime.spawnFailures += 1;
    return;
  }
  if (force || !previous || stateSignature(previous) !== stateSignature(entity)) {
    await handle.setStatusReaction(statusReaction(entity));
    await updateBubble(entity.entity_id, handle, entity);
  }
  if (!previous || force) return;
  if (previous.lifecycle !== entity.lifecycle && TERMINAL.has(entity.lifecycle)) {
    const reaction = entity.lifecycle === "succeeded" ? "success" : entity.lifecycle === "failed" ? "error" : entity.lifecycle === "partial" ? "waiting" : null;
    if (reaction) await handle.react(reaction, { showMessage: false });
  } else if (!previous.unread && entity.unread) {
    await handle.react("waving", { showMessage: false });
  }
}

function statusFor(pets, visibleCount, spawnFailures = 0, health = "online") {
  const overflow = Math.max(0, pets.length - visibleCount);
  const attention = pets.filter((entity) => entity.attention).length;
  const unread = pets.filter((entity) => entity.unread).length;
  const details = [];
  if (health === "offline") details.push("Tycho offline");
  else if (health === "stale") details.push("Data stale");
  details.push(`${visibleCount}/${pets.length} visible`);
  if (overflow > 0) details.push(`+${overflow} overflow`);
  if (attention > 0) details.push(`${attention} attention`);
  if (unread > 0) details.push(`${unread} unread`);
  if (spawnFailures > 0) details.push(`${spawnFailures} pet package errors`);
  return {
    text: details.join(" · "),
    tone: spawnFailures > 0 ? "error" : health !== "online" || attention > 0 ? "warning" : "info",
  };
}

export async function reconcileSnapshot(ctx, value, { force = false } = {}) {
  const snapshot = validateSnapshot(value);
  if (!snapshot) throw new Error("Invalid sanitized adapter snapshot.");
  const state = runtime.state;
  if (!force && state.revision === snapshot.revision) return { changed: false, overflow: Math.max(0, snapshot.pets.length - MAX_VISIBLE_PETS) };
  const config = await ctx.config.get();
  const ids = packageIds(config);
  const currentIds = new Set(snapshot.pets.map((entity) => entity.entity_id));
  for (const id of Object.keys(state.assignments)) {
    if (!currentIds.has(id)) {
      await releasePet(id);
      delete state.assignments[id];
      delete state.last[id];
    }
  }
  for (const entity of [...snapshot.pets].sort((left, right) => left.entity_id.localeCompare(right.entity_id))) {
    if (!state.assignments[entity.entity_id]) {
      const assignmentIndex = Object.keys(state.assignments).length;
      state.assignments[entity.entity_id] = { petId: ids[assignmentIndex % ids.length], slot: null };
    }
  }
  const selected = selectedEntities(snapshot.pets);
  assignSlots(state, selected);
  const selectedIds = new Set(selected.map((entity) => entity.entity_id));
  for (const id of [...runtime.handles.keys()]) {
    if (!selectedIds.has(id)) await releasePet(id);
  }
  runtime.spawnFailures = 0;
  for (const entity of selected.sort((left, right) => state.assignments[left.entity_id].slot - state.assignments[right.entity_id].slot)) {
    await renderEntity(ctx, entity, state.last[entity.entity_id], force);
  }
  state.last = Object.fromEntries(snapshot.pets.map((entity) => [entity.entity_id, entity]));
  state.revision = snapshot.revision;
  await ctx.storage.set(STORAGE_KEY, state);
  await ctx.status.set(statusFor(snapshot.pets, runtime.handles.size, runtime.spawnFailures, snapshot.health));
  return { changed: true, overflow: Math.max(0, snapshot.pets.length - MAX_VISIBLE_PETS) };
}

async function scheduleNext(ctx) {
  if (!runtime?.stopped) await ctx.schedule.once(POLL_SCHEDULE_ID, runtime.backoffMs, () => poll(ctx));
}

export async function poll(ctx, force = false) {
  if (!runtime || runtime.stopped || runtime.polling) return;
  runtime.polling = true;
  try {
    const response = await ctx.net.fetch(ADAPTER_SNAPSHOT_URL, { method: "GET", timeoutMs: 3_000 });
    if (!response.ok) throw new Error("Loopback adapter unavailable.");
    await reconcileSnapshot(ctx, response.json ?? JSON.parse(response.text), { force });
    runtime.backoffMs = POLL_MS;
  } catch {
    runtime.backoffMs = Math.min(Math.max(POLL_MS, runtime.backoffMs * 2), MAX_BACKOFF_MS);
    const previous = Object.values(runtime.state.last).map((entity) => ({ ...entity, health: "offline", attention: true }));
    if (previous.length > 0) {
      const offlineRevision = runtime.state.revision.startsWith("adapter-offline-")
        ? runtime.state.revision
        : `adapter-offline-${runtime.state.revision}`;
      await reconcileSnapshot(ctx, {
        schema_version: 1,
        revision: offlineRevision,
        health: "offline",
        pets: previous,
      });
    } else {
      await ctx.status.set({ text: "Adapter offline · 0/0 visible", tone: "warning" });
    }
  } finally {
    runtime.polling = false;
    await scheduleNext(ctx);
  }
}

async function cleanup() {
  if (!runtime) return;
  runtime.stopped = true;
  try { await runtime.ctx.schedule.cancel(POLL_SCHEDULE_ID); } catch {}
  try { await runtime.ctx.commands.unregister("refresh"); } catch {}
  for (const id of [...runtime.handles.keys()]) await releasePet(id);
  try { await runtime.ctx.pets.default.setStatusReaction(null); } catch {}
  try { await runtime.ctx.status.clear(); } catch {}
  runtime = null;
}

export function register(OpenPetsPlugin) {
  OpenPetsPlugin.register({
    async start(ctx) {
      runtime = {
        ctx,
        state: cleanState(await ctx.storage.get(STORAGE_KEY)),
        handles: new Map(),
        bubbles: new Map(),
        stopped: false,
        polling: false,
        backoffMs: POLL_MS,
        spawnFailures: 0,
      };
      await ctx.commands.register(
        { id: "refresh", title: "$t:command.refresh.title", description: "$t:command.refresh.description" },
        () => poll(ctx, false),
      );
      await poll(ctx, true);
    },
    async stop() {
      await cleanup();
    },
  });
}

if (typeof OpenPetsPlugin !== "undefined") register(OpenPetsPlugin);
