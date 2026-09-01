/// <reference types="@open-pets/plugin-sdk" />

export const ADAPTER_SNAPSHOT_URL = "http://127.0.0.1:7737/snapshot";
export const POLL_SCHEDULE_ID = "tycho-companion-poll";
export const STORAGE_KEY = "sanitized-assignments-v1";
export const ASSIGNMENT_REVISION = 1;
export const MAX_VISIBLE_PETS = 5;
export const MAX_SPAWNED_PETS = 4;

const LIFECYCLES = new Set(["idle", "running", "awaiting-input", "blocked", "succeeded", "failed", "partial", "stopped"]);
const HEALTH = new Set(["online", "stale", "offline"]);
const TERMINAL = new Set(["succeeded", "failed", "partial", "stopped"]);
const POLL_MS = 5_000;
const MAX_BACKOFF_MS = 60_000;

let runtime = null;

function emptyAssignments() {
  return { assignment_revision: ASSIGNMENT_REVISION, assignments: {} };
}

function cleanAssignments(value) {
  const state = emptyAssignments();
  if (value?.assignment_revision !== ASSIGNMENT_REVISION && value?.version !== 1) return state;
  if (!value.assignments || typeof value.assignments !== "object" || Array.isArray(value.assignments)) return state;
  for (const [id, assignment] of Object.entries(value.assignments)) {
    if (!validEntityId(id) || !assignment || typeof assignment !== "object" || Array.isArray(assignment)) continue;
    const petId = validPetPackageId(assignment.petId) ? assignment.petId : "snoopy";
    const slot = Number.isInteger(assignment.slot) && assignment.slot >= 0 && assignment.slot < MAX_VISIBLE_PETS ? assignment.slot : null;
    state.assignments[id] = { petId, slot };
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
  if (!value || typeof value !== "object" || Array.isArray(value) || !validEntityId(value.entity_id)) return null;
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
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  if (value.schema_version !== 1 || typeof value.revision !== "string" || value.revision.length === 0 || value.revision.length > 128) return null;
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

function isCurrent(instance) {
  return runtime === instance && !instance.stopped;
}

function trackWork(instance, operation) {
  const work = operation();
  instance.activeWork.add(work);
  const finished = () => instance.activeWork.delete(work);
  work.then(finished, finished);
  return work;
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

export function transientPollDelay(previousDelay = POLL_MS) {
  return Math.min(Math.max(POLL_MS, previousDelay) * 2, MAX_BACKOFF_MS);
}

function stateSignature(entity) {
  return `${entity.lifecycle}/${entity.active}/${entity.attention}/${entity.health}/${entity.unread}`;
}

function statusReaction(entity) {
  if (entity.health !== "online") return null;
  return { running: "working", "awaiting-input": "waiting", blocked: "error", failed: "error", partial: "waiting" }[entity.lifecycle] ?? null;
}

function lifecycleLabel(lifecycle) {
  return { "awaiting-input": "Input needed", blocked: "Blocked", succeeded: "Succeeded", failed: "Failed", partial: "Partial", stopped: "Stopped" }[lifecycle] ?? "";
}

function bubbleText(entity) {
  let label = entity.health === "offline" ? "Tycho offline" : entity.health === "stale" ? "Data stale" : lifecycleLabel(entity.lifecycle);
  if (entity.unread) label = label ? `${label} · unread` : "Unread";
  return label;
}

function selectedEntities(pets) {
  return [...pets].sort((left, right) => visibilityPriority(right) - visibilityPriority(left) || left.entity_id.localeCompare(right.entity_id)).slice(0, MAX_VISIBLE_PETS);
}

function assignSlots(assignments, selected) {
  const selectedIds = new Set(selected.map((entity) => entity.entity_id));
  const used = new Set();
  for (const id of selectedIds) {
    const slot = assignments[id]?.slot;
    if (Number.isInteger(slot) && !used.has(slot)) used.add(slot);
    else if (assignments[id]) assignments[id].slot = null;
  }
  for (const entity of selected) {
    if (assignments[entity.entity_id].slot !== null) continue;
    for (let slot = 0; slot < MAX_VISIBLE_PETS; slot += 1) {
      if (!used.has(slot)) {
        assignments[entity.entity_id].slot = slot;
        used.add(slot);
        break;
      }
    }
  }
  for (const [id, assignment] of Object.entries(assignments)) {
    if (!selectedIds.has(id)) assignment.slot = null;
  }
}

async function dismissBubble(instance, id) {
  const bubble = instance.bubbles.get(id);
  if (!bubble) return;
  instance.bubbles.delete(id);
  try { await bubble.dismiss(); } catch {}
}

async function releasePet(instance, id) {
  await dismissBubble(instance, id);
  const entry = instance.handles.get(id);
  if (!entry) return;
  instance.handles.delete(id);
  try { await entry.handle.setStatusReaction(null); } catch {}
  if (entry.spawned) {
    try { await entry.handle.close(); } catch {}
  }
}

async function ensurePet(instance, id, assignment) {
  const current = instance.handles.get(id);
  if (current?.slot === assignment.slot && (!current.spawned || current.petId === assignment.petId)) return current.handle;
  if (current) {
    await releasePet(instance, id);
    if (!isCurrent(instance)) return null;
  }
  if (assignment.slot === 0) {
    instance.handles.set(id, { handle: instance.ctx.pets.default, spawned: false, slot: 0, petId: "default" });
    return instance.ctx.pets.default;
  }
  const handle = await instance.ctx.pets.spawn({ petId: assignment.petId, name: `Tycho pet ${assignment.slot + 1}`, ephemeral: true });
  if (!isCurrent(instance)) {
    try { await handle.close(); } catch {}
    return null;
  }
  instance.handles.set(id, { handle, spawned: true, slot: assignment.slot, petId: assignment.petId });
  return handle;
}

async function updateBubble(instance, id, handle, entity) {
  const text = bubbleText(entity);
  const existing = instance.bubbles.get(id);
  if (!text) {
    await dismissBubble(instance, id);
    return isCurrent(instance);
  }
  const spec = { text, sticky: true, pin: true, dismissOn: [], priority: entity.attention ? "high" : "normal" };
  if (existing) {
    try {
      await existing.update(spec);
      return isCurrent(instance);
    } catch {
      if (!isCurrent(instance)) return false;
      instance.bubbles.delete(id);
    }
  }
  const bubble = await handle.speak(spec);
  if (!isCurrent(instance)) {
    try { await bubble.dismiss(); } catch {}
    return false;
  }
  instance.bubbles.set(id, bubble);
  return true;
}

async function renderEntity(instance, entity, previous, force) {
  const assignment = instance.assignmentState.assignments[entity.entity_id];
  let handle;
  try {
    handle = await ensurePet(instance, entity.entity_id, assignment);
    if (!isCurrent(instance) || !handle) return;
  } catch {
    if (isCurrent(instance)) instance.spawnFailures += 1;
    return;
  }
  if (force || !previous || stateSignature(previous) !== stateSignature(entity)) {
    await handle.setStatusReaction(statusReaction(entity));
    if (!isCurrent(instance)) return;
    await updateBubble(instance, entity.entity_id, handle, entity);
    if (!isCurrent(instance)) return;
  }
  if (!previous || force) return;
  if (previous.lifecycle !== entity.lifecycle && TERMINAL.has(entity.lifecycle)) {
    const reaction = entity.lifecycle === "succeeded" ? "success" : entity.lifecycle === "failed" ? "error" : entity.lifecycle === "partial" ? "waiting" : null;
    if (reaction) {
      await handle.react(reaction, { showMessage: false });
      if (!isCurrent(instance)) return;
    }
  } else if (!previous.unread && entity.unread) {
    await handle.react("waving", { showMessage: false });
    if (!isCurrent(instance)) return;
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
  return { text: details.join(" · "), tone: spawnFailures > 0 ? "error" : health !== "online" || attention > 0 ? "warning" : "info" };
}

async function reconcileValidated(instance, snapshot, force) {
  if (!isCurrent(instance)) return { changed: false, overflow: 0 };
  if (!force && instance.lastRevision === snapshot.revision) return { changed: false, overflow: Math.max(0, snapshot.pets.length - MAX_VISIBLE_PETS) };
  const config = await instance.ctx.config.get();
  if (!isCurrent(instance)) return { changed: false, overflow: 0 };
  const ids = packageIds(config);
  const assignments = instance.assignmentState.assignments;
  const currentIds = new Set(snapshot.pets.map((entity) => entity.entity_id));
  for (const id of Object.keys(assignments)) {
    if (!currentIds.has(id)) {
      await releasePet(instance, id);
      if (!isCurrent(instance)) return { changed: false, overflow: 0 };
      delete assignments[id];
      delete instance.lastById[id];
    }
  }
  for (const entity of [...snapshot.pets].sort((left, right) => left.entity_id.localeCompare(right.entity_id))) {
    if (!assignments[entity.entity_id]) {
      const assignmentIndex = Object.keys(assignments).length;
      assignments[entity.entity_id] = { petId: ids[assignmentIndex % ids.length], slot: null };
    }
  }
  const selected = selectedEntities(snapshot.pets);
  assignSlots(assignments, selected);
  const selectedIds = new Set(selected.map((entity) => entity.entity_id));
  for (const id of [...instance.handles.keys()]) {
    if (!selectedIds.has(id)) {
      await releasePet(instance, id);
      if (!isCurrent(instance)) return { changed: false, overflow: 0 };
    }
  }
  instance.spawnFailures = 0;
  for (const entity of selected.sort((left, right) => assignments[left.entity_id].slot - assignments[right.entity_id].slot)) {
    await renderEntity(instance, entity, instance.lastById[entity.entity_id], force);
    if (!isCurrent(instance)) return { changed: false, overflow: 0 };
  }
  instance.lastById = Object.fromEntries(snapshot.pets.map((entity) => [entity.entity_id, entity]));
  instance.lastRevision = snapshot.revision;
  await instance.ctx.storage.set(STORAGE_KEY, instance.assignmentState);
  if (!isCurrent(instance)) return { changed: false, overflow: 0 };
  await instance.ctx.status.set(statusFor(snapshot.pets, instance.handles.size, instance.spawnFailures, snapshot.health));
  if (!isCurrent(instance)) return { changed: false, overflow: 0 };
  return { changed: true, overflow: Math.max(0, snapshot.pets.length - MAX_VISIBLE_PETS) };
}

export function reconcileSnapshot(ctx, value, { force = false } = {}) {
  const instance = runtime;
  if (!instance || instance.ctx !== ctx || !isCurrent(instance)) return Promise.resolve({ changed: false, overflow: 0 });
  const snapshot = validateSnapshot(value);
  if (!snapshot) return Promise.reject(new Error("Invalid sanitized adapter snapshot."));
  return trackWork(instance, () => reconcileValidated(instance, snapshot, force));
}

async function scheduleNext(instance) {
  if (!isCurrent(instance)) return;
  await instance.ctx.schedule.once(POLL_SCHEDULE_ID, instance.backoffMs, () => poll(instance.ctx, false, instance));
  if (!isCurrent(instance)) {
    try { await instance.ctx.schedule.cancel(POLL_SCHEDULE_ID); } catch {}
  }
}

async function runPoll(instance, force) {
  const ctx = instance.ctx;
  instance.polling = true;
  try {
    const response = await ctx.net.fetch(ADAPTER_SNAPSHOT_URL, { method: "GET", timeoutMs: 3_000 });
    if (!isCurrent(instance)) return;
    if (!response.ok) throw new Error("Loopback adapter unavailable.");
    const snapshot = validateSnapshot(response.json ?? JSON.parse(response.text));
    if (!snapshot) {
      const error = new Error("Invalid sanitized adapter snapshot.");
      error.invalidSnapshot = true;
      throw error;
    }
    await reconcileValidated(instance, snapshot, force);
    if (!isCurrent(instance)) return;
    instance.backoffMs = POLL_MS;
  } catch (error) {
    if (!isCurrent(instance)) return;
    instance.backoffMs = transientPollDelay(instance.backoffMs);
    if (error?.invalidSnapshot) {
      await ctx.status.set({ text: "Adapter response rejected · last valid state preserved", tone: "error" });
      if (!isCurrent(instance)) return;
    } else {
      const previous = Object.values(instance.lastById).map((entity) => ({ ...entity, health: "offline", attention: true }));
      if (previous.length > 0) {
        const offlineRevision = instance.lastRevision.startsWith("adapter-offline-") ? instance.lastRevision : `adapter-offline-${instance.lastRevision}`;
        await reconcileValidated(instance, { schema_version: 1, revision: offlineRevision, health: "offline", pets: previous }, false);
        if (!isCurrent(instance)) return;
      } else {
        await ctx.status.set({ text: "Adapter offline · 0/0 visible", tone: "warning" });
        if (!isCurrent(instance)) return;
      }
    }
  } finally {
    if (isCurrent(instance)) {
      instance.polling = false;
      await scheduleNext(instance);
    }
  }
}

export function poll(ctx, force = false, captured = runtime) {
  const instance = captured;
  if (!instance || instance.ctx !== ctx || !isCurrent(instance) || instance.polling) return Promise.resolve();
  return trackWork(instance, () => runPoll(instance, force));
}

async function cleanup() {
  const instance = runtime;
  if (!instance) return;
  instance.stopped = true;
  runtime = null;
  try { await instance.ctx.schedule.cancel(POLL_SCHEDULE_ID); } catch {}
  await Promise.allSettled([...instance.activeWork]);
  try { await instance.ctx.commands.unregister("refresh"); } catch {}
  for (const id of [...instance.handles.keys()]) await releasePet(instance, id);
  try { await instance.ctx.pets.default.setStatusReaction(null); } catch {}
  try { await instance.ctx.status.clear(); } catch {}
  instance.lastById = {};
  instance.lastRevision = "";
  instance.assignmentState = emptyAssignments();
  instance.bubbles.clear();
  instance.handles.clear();
  instance.activeWork.clear();
}

async function startRuntime(instance) {
  const { ctx } = instance;
  const stored = await ctx.storage.get(STORAGE_KEY);
  if (!isCurrent(instance)) return;
  instance.assignmentState = cleanAssignments(stored);
  await ctx.commands.register(
    { id: "refresh", title: "$t:command.refresh.title", description: "$t:command.refresh.description" },
    () => poll(ctx, false, instance),
  );
  if (!isCurrent(instance)) return;
  await poll(ctx, true, instance);
}

export function register(OpenPetsPlugin) {
  OpenPetsPlugin.register({
    async start(ctx) {
      const instance = {
        ctx,
        assignmentState: emptyAssignments(),
        lastById: {},
        lastRevision: "",
        handles: new Map(),
        bubbles: new Map(),
        stopped: false,
        polling: false,
        backoffMs: POLL_MS,
        spawnFailures: 0,
        activeWork: new Set(),
      };
      runtime = instance;
      await trackWork(instance, () => startRuntime(instance));
    },
    async stop() {
      await cleanup();
    },
  });
}

if (typeof OpenPetsPlugin !== "undefined") register(OpenPetsPlugin);
