# OpenPets comparison prototype evidence

Evidence recorded on 2026-09-01 from macOS on the repository's clean Godot baseline `03278bf` and OpenPets commit `6c8187c4b67d4e27c6e4e573530bd74b5e998c75`.

## Result

The standalone plugin boundary is sufficient. The prototype needed no OpenPets fork, OpenPets core change, Tycho change, or unsafe credential persistence. It recognizes all required conditions, preserves stable opaque pet assignments, caps the scene at five pets, reports overflow, and does not replay transitions on repeated snapshots or initial rendering after restart.

OpenPets is materially quieter at idle but materially heavier in memory. Its separate pet windows and pinned bubbles also create more visual clutter than the single Godot strip. This experiment supports further OpenPets testing; it does not justify replacing the Godot baseline yet.

## State recognition and clutter

| Condition | Godot baseline | OpenPets prototype | Deterministic evidence |
| --- | --- | --- | --- |
| Running | Animated work pose | Persistent `working` reaction | SDK harness asserts `working` |
| Awaiting input | Waiting pose/lantern | Persistent `waiting` plus `Input needed` | SDK harness asserts reaction and bubble |
| Blocked | Closed-gate cue | Persistent `error` plus `Blocked` | SDK harness asserts reaction and bubble |
| Unread terminal | Mailbox cue independent of result | Terminal label with `unread`; one transition reaction only | SDK harness asserts `Succeeded · unread` and no replay |
| Failure | Failed pose | Persistent `error` plus `Failed` | SDK harness asserts reaction and bubble |
| Stale/offline | Frozen, desaturated scene | Lifecycle retained with `Data stale` or `Tycho offline` | Adapter and SDK tests assert preservation |
| Loading/unauthorized server | Connecting/offline wrapper | `loading` becomes stale attention; `unauthorized` becomes offline attention | Contract fixtures assert lifecycle preservation and attention |
| Partial | Partial pose | Persistent `waiting`, `Partial`, and one transition cue | SDK 3.3.0 harness asserts cue and no replay |

The target conditions remain textually distinct without exposing agent or project labels. Unread stays a boolean overlay instead of replacing lifecycle. Repeated snapshots produce no terminal or unread replay. On plugin restart, lifecycle history is intentionally absent: the first snapshot restores cosmetic assignments and persistent cues without treating existing terminal/unread state as a new transition.

Godot renders all agents inside one 300 px bottom strip. OpenPets uses the default pet plus up to four independent always-on-top windows; up to five attention bubbles may be pinned at once. The plugin avoids bubbles for ordinary running and idle states, ranks attention before running/idle, and publishes `+N overflow`, but its worst-case footprint is still five windows and five state cues. That is a clear clutter regression against the shoreline composition.

## CPU, memory, and focus

Both GUI hosts ran for 12 seconds with no live Tycho configuration. OpenPets was built locally from the pinned source, loaded the unpacked plugin with automatic development approval, and read an empty sanitized loopback snapshot. RSS is the sum of the root process and all descendants. `%CPU` is `ps` lifetime CPU at the sample.

| Runtime | Processes | RSS | CPU | Frontmost app before/after |
| --- | ---: | ---: | ---: | --- |
| Godot baseline | 1 | 215,120 KiB | 44.6% | `ghostty` / `ghostty` |
| OpenPets host + enabled plugin | 6 | 544,288 KiB | 2.9% | `ghostty` / `ghostty` |
| Loopback adapter | 1 | 54,912 KiB | 0.0% | n/a |
| OpenPets total | 7 | 599,200 KiB | 2.9% sampled total | unchanged |

On this run, OpenPets plus the adapter used about 2.8 times the Godot memory but only about 6% of its sampled CPU. Godot's idle caretaker loop remains active; OpenPets and the adapter sleep between scheduled work. These are prototype measurements from one machine, not release benchmarks.

Neither runtime stole focus at launch. OpenPets creates plugin pet windows with `showInactive()`, and this plugin requests no move, cursor, input, panel, notification, or system capability. The pinned host still marks passive pet windows focusable on macOS and Windows, while Linux passive windows are non-focusable; clicking a pet can therefore differ from launch behavior. Godot also does not explicitly set a no-focus flag and intentionally intercepts its painted strip on Windows. Neither prototype proves the final zero-focus, click-through requirement across platforms.

## Reproduction

Godot GUI sample:

```sh
godot --path godot &
# After 12 seconds: ps -o rss=,%cpu= -p $!
```

OpenPets host sample:

1. Build the pinned OpenPets checkout from source.
2. Start `openpets/adapter/idle-resource-check.mjs` on port 7737 for the measurement window.
3. Launch the built desktop with a fresh user-data directory, `OPENPETS_DISABLE_PLUGIN_CATALOG=1`, and `OPENPETS_DEV_PLUGIN_PATHS` set to `openpets/plugin`.
4. After 12 seconds, sum RSS and CPU for the Electron root and descendants with `ps`.
5. Confirm the temporary plugin record is enabled and not broken, then remove the temporary user data.

The deterministic microbenchmark is easier to repeat:

```sh
cd openpets
npm run benchmark
```

Recorded exact-head output for 100 sanitized entities was 0.279 ms per adapter reconciliation, 0.01251 ms per unchanged plugin reconciliation, 7,026 bytes of persisted cosmetic assignment state, and 64.1 MiB RSS for the Node benchmark process. The five-second adapter-only resource check passed its 96 MiB ceiling. These Node checks exclude the Electron host and therefore do not replace the full-host measurement above.

## Exact-head review evidence

- `npm test`: 26/26 pass with the SDK harness pinned exactly to 3.3.0.
- `npm audit --audit-level=low`: 0 vulnerabilities.
- Research-pinned source CLI validator: pass. Research-pinned desktop manifest validator: pass. The published CLI 3.3.0 still rejects `network:local`, as documented under limitations.
- Non-empty pinned desktop lifecycle: two sanitized assignments caused one default pet plus one successful `snoopy` spawn; running changed to partial and the host recorded one `waiting` reaction; removal returned persisted assignments to zero. The plugin stayed enabled and unbroken, and the host logged no SDK dispatch failure.
- The non-empty run used only `adapter/real-host-lifecycle-fixture.mjs`, a random in-memory placeholder credential, synthetic opaque source rows, a temporary profile, and a temporary installed test pet. It contained no live Tycho secret or activity.
- Malformed server/agent/status fixtures and successful oversized, invalid-JSON, unsupported-schema, and malformed responses preserve the prior assignment map. The latter responses serve the preserved lifecycle as stale, and the plugin renders that degraded state without respawning or changing cosmetic assignments.
- Delayed fetch and delayed `storage.set` unload regressions prove cleanup blocks new work, waits for admitted SDK operations, and allows no SDK commit after stop returns.
- A repeat pinned-desktop launch left `ghostty` frontmost before and after; terminating the host and adapter left no matching process.

## Privacy and persistence evidence

- The adapter binds only `127.0.0.1`, accepts only `GET /snapshot`, sets `Cache-Control: no-store`, and makes only authenticated `GET /servers/activity` calls.
- Adapter output contains only schema/revision, aggregate counts/health, and opaque entity rows with lifecycle, active, attention, unread, and health.
- Persisted adapter assignments contain SHA-256 composite-key digests and random UUIDs, never raw server or agent keys. The file is mode `0600` and atomically replaced.
- Plugin storage contains only `assignment_revision`, opaque assignment IDs, installed pet package IDs, and slots. Lifecycle, active, attention, unread, health, source revisions, and transition history are memory-only and cleared on unload.
- The manifest declares one exact loopback host and no credential field. The plugin does not log data.

## Limitations

- The pinned source supports `network:local`; the published CLI 3.3.0 validator does not. The pinned desktop validator accepted the manifest, and the locally built host loaded it enabled and unbroken.
- Spawned windows require installed non-built-in pet packages. Missing configured packages reduce visible pets and surface a package-error status.
- OpenPets' four-spawn quota forces use of the user's default pet for the fifth slot.
- OpenPets cannot dim arbitrary pets for stale/offline through the reaction API, so the prototype uses explicit text.
- Resource and focus results cover one macOS session. Windows fullscreen, Linux Wayland, workspace changes, clicks, and sleep/wake still need manual target-platform testing.
- The adapter currently accepts its credential only from process environment. An OS credential-store launcher would be required before production use.
- After a confirmed 401 the adapter deliberately remains offline until process restart or explicit in-process reconfiguration. It does not expose remote reconfiguration over loopback.
