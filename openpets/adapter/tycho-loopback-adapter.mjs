import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

export const ADAPTER_HOST = "127.0.0.1";
export const ADAPTER_PORT = 7737;
export const SNAPSHOT_SCHEMA_VERSION = 1;
export const MAX_ACTIVITY_BYTES = 512 * 1024;
export const MAX_AGENTS = 200;
export const POLL_INTERVAL_MS = 5_000;
export const MAX_POLL_BACKOFF_MS = 60_000;
export const REQUEST_TIMEOUT_MS = 4_000;

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

const HEALTH_RANK = { online: 0, stale: 1, offline: 2 };
const SERVER_STATUSES = new Set(["online", "loading", "unauthorized", "offline"]);

function boundedString(value, maxLength = 128) {
  return typeof value === "string" && value.length > 0 && value.length <= maxLength ? value : null;
}

function defaultStateFile() {
  const base = process.env.XDG_STATE_HOME || join(homedir(), ".local", "state");
  return join(base, "tycho-companion", "openpets-adapter-state.json");
}

function privateKey(serverKey, agentKey) {
  return createHash("sha256").update(serverKey).update("\0").update(agentKey).digest("hex");
}

export class AssignmentStore {
  constructor(filePath = defaultStateFile()) {
    this.filePath = filePath;
    this.assignments = new Map();
    this.dirty = false;
  }

  async load() {
    try {
      const parsed = JSON.parse(await readFile(this.filePath, "utf8"));
      if (parsed?.version !== 1 || typeof parsed.assignments !== "object" || Array.isArray(parsed.assignments)) {
        throw new Error("invalid assignment state");
      }
      for (const [key, value] of Object.entries(parsed.assignments)) {
        if (/^[a-f0-9]{64}$/.test(key) && /^[a-f0-9-]{36}$/.test(value)) this.assignments.set(key, value);
      }
    } catch (error) {
      if (error?.code !== "ENOENT") throw new Error("Adapter assignment state could not be read.");
      this.dirty = true;
    }
  }

  idFor(serverKey, agentKey) {
    const key = privateKey(serverKey, agentKey);
    let id = this.assignments.get(key);
    if (!id) {
      id = randomUUID();
      this.assignments.set(key, id);
      this.dirty = true;
    }
    return { key, id };
  }

  async retain(keys) {
    const retained = new Set(keys);
    for (const key of this.assignments.keys()) {
      if (!retained.has(key)) {
        this.assignments.delete(key);
        this.dirty = true;
      }
    }
    await this.save();
  }

  async save() {
    if (!this.dirty) return;
    await mkdir(dirname(this.filePath), { recursive: true, mode: 0o700 });
    const temporary = `${this.filePath}.${process.pid}.${randomUUID()}.tmp`;
    const document = JSON.stringify({ version: 1, assignments: Object.fromEntries([...this.assignments].sort()) });
    await writeFile(temporary, document, { encoding: "utf8", mode: 0o600, flag: "wx" });
    await rename(temporary, this.filePath);
    this.dirty = false;
  }
}

export function validateTychoOrigin(value) {
  try {
    const url = new URL(value);
    if (url.username || url.password || url.pathname !== "/" || url.search || url.hash) return null;
    const loopback = url.hostname === "127.0.0.1" || url.hostname === "localhost";
    const privateHttps = !url.hostname.includes(".") || url.hostname.endsWith(".ts.net");
    if ((url.protocol === "http:" && loopback) || (url.protocol === "https:" && privateHttps)) {
      return url.origin;
    }
  } catch {}
  return null;
}

function effectiveLifecycle(agent) {
  if (agent.blocked === true) return "blocked";
  if (agent.awaiting_input === true) return "awaiting-input";
  return agent.status;
}

function serverHealth(server) {
  if (server.status === "unauthorized" || server.status === "offline") return "offline";
  if (server.stale || server.status === "loading") return "stale";
  return "online";
}

function attentionFor(lifecycle, unread, health) {
  return health !== "online" || unread || ["awaiting-input", "blocked", "succeeded", "failed", "partial", "stopped"].includes(lifecycle);
}

function snapshotRevision(entities, health) {
  return createHash("sha256").update(JSON.stringify({ entities, health })).digest("hex");
}

export async function sanitizeActivity(activity, store) {
  if (activity?.schema_version !== 1 || !Array.isArray(activity.servers)) throw new Error("Unsupported activity snapshot.");
  const validatedServers = [];
  let agentCount = 0;
  const serverKeys = new Set();
  const identities = new Set();

  for (const candidate of activity.servers) {
    if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) throw new Error("Invalid activity server row.");
    const key = boundedString(candidate.key);
    if (!key || !SERVER_STATUSES.has(candidate.status) || typeof candidate.stale !== "boolean" || !Array.isArray(candidate.agents)) {
      throw new Error("Invalid activity server row.");
    }
    if (serverKeys.has(key)) throw new Error("Duplicate activity server row.");
    serverKeys.add(key);
    const agents = [];
    for (const row of candidate.agents) {
      if (!row || typeof row !== "object" || Array.isArray(row)) throw new Error("Invalid activity agent row.");
      const agentKey = boundedString(row.key);
      if (!agentKey || !LIFECYCLES.has(row.status) || typeof row.unread !== "boolean" ||
          typeof row.archived !== "boolean" || typeof row.awaiting_input !== "boolean" || typeof row.blocked !== "boolean") {
        throw new Error("Invalid activity agent row.");
      }
      const identity = `${key}\0${agentKey}`;
      if (identities.has(identity)) throw new Error("Duplicate activity agent row.");
      identities.add(identity);
      agents.push({
        key: agentKey,
        status: row.status,
        unread: row.unread,
        archived: row.archived,
        awaiting_input: row.awaiting_input,
        blocked: row.blocked,
      });
      if (!row.archived && ++agentCount > MAX_AGENTS) throw new Error("Activity snapshot has too many agents.");
    }
    validatedServers.push({ key, status: candidate.status, stale: candidate.stale, agents });
  }

  const entities = [];
  const retainedKeys = [];
  let aggregateHealth = "online";

  for (const server of validatedServers) {
    const serverKey = server.key;
    const health = serverHealth(server);
    if (HEALTH_RANK[health] > HEALTH_RANK[aggregateHealth]) aggregateHealth = health;
    for (const agent of server.agents) {
      if (agent.archived) continue;
      const agentKey = agent.key;
      const assignment = store.idFor(serverKey, agentKey);
      retainedKeys.push(assignment.key);
      const lifecycle = effectiveLifecycle(agent);
      const unread = agent.unread === true;
      entities.push({
        entity_id: assignment.id,
        lifecycle,
        active: lifecycle === "running",
        attention: attentionFor(lifecycle, unread, health),
        unread,
        health,
      });
    }
  }

  entities.sort((left, right) => left.entity_id.localeCompare(right.entity_id));
  await store.retain(retainedKeys);
  const counts = {
    total: entities.length,
    active: entities.filter((entity) => entity.active).length,
    attention: entities.filter((entity) => entity.attention).length,
    unread: entities.filter((entity) => entity.unread).length,
  };
  return {
    schema_version: SNAPSHOT_SCHEMA_VERSION,
    revision: snapshotRevision(entities, aggregateHealth),
    health: aggregateHealth,
    counts,
    pets: entities,
  };
}

function offlineSnapshot(previous) {
  const pets = previous.pets.map((entity) => ({ ...entity, health: "offline", attention: true }));
  return {
    schema_version: SNAPSHOT_SCHEMA_VERSION,
    revision: snapshotRevision(pets, "offline"),
    health: "offline",
    counts: {
      total: pets.length,
      active: pets.filter((entity) => entity.active).length,
      attention: pets.length,
      unread: pets.filter((entity) => entity.unread).length,
    },
    pets,
  };
}

export class TychoPoller {
  constructor({ origin, credential, store, fetchImpl = fetch, timeoutMs = REQUEST_TIMEOUT_MS }) {
    this.origin = origin;
    this.credential = credential;
    this.store = store;
    this.fetchImpl = fetchImpl;
    this.timeoutMs = timeoutMs;
    this.snapshot = offlineSnapshot({ pets: [] });
    this.outcome = "transient";
    this.authenticationBlocked = false;
  }

  async poll() {
    if (this.authenticationBlocked) return this.snapshot;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    let preserveLastValid = false;
    try {
      const response = await this.fetchImpl(`${this.origin}/servers/activity`, {
        method: "GET",
        headers: { Authorization: `Bearer ${this.credential}`, Accept: "application/json" },
        redirect: "error",
        signal: controller.signal,
      });
      if (response.status === 401) {
        this.authenticationBlocked = true;
        this.outcome = "authentication";
        this.snapshot = offlineSnapshot(this.snapshot);
        return this.snapshot;
      }
      if (!response.ok) throw new Error("Tycho activity request failed.");
      preserveLastValid = true;
      const declaredBytes = Number(response.headers.get("content-length"));
      if (Number.isFinite(declaredBytes) && declaredBytes > MAX_ACTIVITY_BYTES) throw new Error("Tycho activity response was too large.");
      const reader = response.body?.getReader();
      const chunks = [];
      let receivedBytes = 0;
      if (reader) {
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          receivedBytes += value.byteLength;
          if (receivedBytes > MAX_ACTIVITY_BYTES) {
            await reader.cancel();
            throw new Error("Tycho activity response was too large.");
          }
          chunks.push(value);
        }
      }
      const body = reader ? new TextDecoder().decode(Buffer.concat(chunks)) : await response.text();
      if (Buffer.byteLength(body) > MAX_ACTIVITY_BYTES) throw new Error("Tycho activity response was too large.");
      this.snapshot = await sanitizeActivity(JSON.parse(body), this.store);
      this.outcome = "success";
    } catch {
      this.outcome = "transient";
      if (!preserveLastValid) this.snapshot = offlineSnapshot(this.snapshot);
    } finally {
      clearTimeout(timer);
    }
    return this.snapshot;
  }
}

export function transientBackoffMs(failureCount) {
  const exponent = Math.max(0, Math.min(30, Number.isInteger(failureCount) ? failureCount - 1 : 0));
  return Math.min(POLL_INTERVAL_MS * (2 ** exponent), MAX_POLL_BACKOFF_MS);
}

export class PollController {
  constructor({ poller, schedule = setTimeout, cancel = clearTimeout }) {
    this.poller = poller;
    this.schedule = schedule;
    this.cancel = cancel;
    this.timer = null;
    this.stopped = false;
    this.transientFailures = 0;
  }

  async start() {
    await this.tick();
  }

  async tick() {
    if (this.stopped || this.poller.authenticationBlocked) return;
    await this.poller.poll();
    if (this.stopped || this.poller.authenticationBlocked) return;
    if (this.poller.outcome === "success") this.transientFailures = 0;
    else this.transientFailures += 1;
    const delay = this.poller.outcome === "success" ? POLL_INTERVAL_MS : transientBackoffMs(this.transientFailures);
    this.timer = this.schedule(() => this.tick(), delay);
    this.timer?.unref?.();
  }

  stop() {
    this.stopped = true;
    if (this.timer !== null) this.cancel(this.timer);
    this.timer = null;
  }

  async reconfigure({ origin, credential }) {
    const safeOrigin = validateTychoOrigin(origin);
    if (!safeOrigin || typeof credential !== "string" || credential.length === 0) throw new Error("Safe Tycho adapter configuration is required.");
    if (this.timer !== null) this.cancel(this.timer);
    this.timer = null;
    this.transientFailures = 0;
    this.poller.origin = safeOrigin;
    this.poller.credential = credential;
    this.poller.authenticationBlocked = false;
    this.poller.outcome = "transient";
    await this.tick();
  }
}

export async function startAdapter({ origin, credential, stateFile, port = ADAPTER_PORT, fetchImpl = fetch }) {
  const safeOrigin = validateTychoOrigin(origin);
  if (!safeOrigin || typeof credential !== "string" || credential.length === 0) throw new Error("Safe Tycho adapter configuration is required.");
  const store = new AssignmentStore(stateFile);
  await store.load();
  const poller = new TychoPoller({ origin: safeOrigin, credential, store, fetchImpl });
  const controller = new PollController({ poller });
  await controller.start();

  const server = createServer((request, response) => {
    if (request.method !== "GET") {
      response.writeHead(405, { Allow: "GET", "Cache-Control": "no-store" });
      response.end();
      return;
    }
    if (request.url !== "/snapshot") {
      response.writeHead(404, { "Cache-Control": "no-store" });
      response.end();
      return;
    }
    response.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    response.end(JSON.stringify(poller.snapshot));
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, ADAPTER_HOST, resolve);
  });
  return {
    server,
    poller,
    address: server.address(),
    reconfigure: (configuration) => controller.reconfigure(configuration),
    async close() {
      controller.stop();
      await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
    },
  };
}

async function main() {
  try {
    const running = await startAdapter({
      origin: process.env.TYCHO_ORIGIN,
      credential: process.env.TYCHO_TOKEN,
      stateFile: process.env.TYCHO_OPENPETS_STATE_FILE,
      port: ADAPTER_PORT,
    });
    process.stdout.write(`Tycho OpenPets adapter listening on ${ADAPTER_HOST}:${running.address.port}.\n`);
    const stop = async () => {
      await running.close();
      process.exit(0);
    };
    process.once("SIGINT", stop);
    process.once("SIGTERM", stop);
  } catch {
    process.stderr.write("Tycho OpenPets adapter could not start. Check its private environment configuration.\n");
    process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] || "").href) await main();
