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
  return LIFECYCLES.has(agent.status) ? agent.status : "idle";
}

function serverHealth(server) {
  const status = typeof server.status === "string" ? server.status.toLowerCase() : "";
  if (["offline", "disconnected", "unreachable"].includes(status)) return "offline";
  if (server.stale === true || status === "stale") return "stale";
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
  const entities = [];
  const retainedKeys = [];
  let aggregateHealth = "online";

  for (const server of activity.servers) {
    const serverKey = boundedString(server?.key);
    if (!serverKey || !Array.isArray(server.agents)) continue;
    const health = serverHealth(server);
    if (HEALTH_RANK[health] > HEALTH_RANK[aggregateHealth]) aggregateHealth = health;
    for (const agent of server.agents) {
      if (entities.length >= MAX_AGENTS) break;
      if (agent?.archived === true) continue;
      const agentKey = boundedString(agent?.key);
      if (!agentKey) continue;
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
  }

  async poll() {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetchImpl(`${this.origin}/servers/activity`, {
        method: "GET",
        headers: { Authorization: `Bearer ${this.credential}`, Accept: "application/json" },
        redirect: "error",
        signal: controller.signal,
      });
      if (!response.ok) throw new Error("Tycho activity request failed.");
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
    } catch {
      this.snapshot = offlineSnapshot(this.snapshot);
    } finally {
      clearTimeout(timer);
    }
    return this.snapshot;
  }
}

export async function startAdapter({ origin, credential, stateFile, port = ADAPTER_PORT, fetchImpl = fetch }) {
  const safeOrigin = validateTychoOrigin(origin);
  if (!safeOrigin || typeof credential !== "string" || credential.length === 0) throw new Error("Safe Tycho adapter configuration is required.");
  const store = new AssignmentStore(stateFile);
  await store.load();
  const poller = new TychoPoller({ origin: safeOrigin, credential, store, fetchImpl });
  await poller.poll();

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
  const interval = setInterval(() => void poller.poll(), POLL_INTERVAL_MS);
  interval.unref?.();
  return {
    server,
    poller,
    address: server.address(),
    async close() {
      clearInterval(interval);
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
