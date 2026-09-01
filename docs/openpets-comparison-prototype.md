# OpenPets comparison prototype evidence

Evidence recorded on 2026-09-01 from macOS on the repository's clean Godot baseline `03278bf` and OpenPets commit `6c8187c4b67d4e27c6e4e573530bd74b5e998c75`.

## Result

The standalone plugin boundary is sufficient. The prototype needed no OpenPets fork, OpenPets core change, Tycho change, or unsafe credential persistence. It recognizes all required conditions, preserves stable opaque pet assignments, caps the scene at five pets, reports overflow, and does not replay transitions on repeated or restarted snapshots.

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

The six target conditions remain textually distinct without exposing agent or project labels. Unread stays a boolean overlay instead of replacing lifecycle. Repeated snapshots, adapter restart, and plugin restart produce no terminal or unread replay.

Godot renders all agents inside one 300 px bottom strip. OpenPets uses the default pet plus up to four independent always-on-top windows; up to four attention bubbles may be pinned at once. The plugin avoids bubbles for ordinary running and idle states, ranks attention before running/idle, and publishes `+N overflow`, but its worst-case footprint is still five windows and five state cues. That is a clear clutter regression against the shoreline composition.

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

Recorded output for 100 sanitized entities was 0.265 ms per adapter reconciliation, 0.01266 ms per unchanged plugin reconciliation, 24,866 bytes of persisted sanitized plugin state, and 63.9 MiB RSS for the Node benchmark process. This excludes the Electron host and therefore does not replace the full-host measurement above.

## Privacy and persistence evidence

- The adapter binds only `127.0.0.1`, accepts only `GET /snapshot`, sets `Cache-Control: no-store`, and makes only authenticated `GET /servers/activity` calls.
- Adapter output contains only schema/revision, aggregate counts/health, and opaque entity rows with lifecycle, active, attention, unread, and health.
- Persisted adapter assignments contain SHA-256 composite-key digests and random UUIDs, never raw server or agent keys. The file is mode `0600` and atomically replaced.
- Plugin storage contains only opaque assignment IDs, installed pet package IDs, slots, and the last sanitized state.
- The manifest declares one exact loopback host and no credential field. The plugin does not log data.

## Limitations

- The pinned source supports `network:local`; the published CLI 3.3.0 validator does not. The pinned desktop validator accepted the manifest, and the locally built host loaded it enabled and unbroken.
- Spawned windows require installed non-built-in pet packages. Missing configured packages reduce visible pets and surface a package-error status.
- OpenPets' four-spawn quota forces use of the user's default pet for the fifth slot.
- OpenPets cannot dim arbitrary pets for stale/offline through the reaction API, so the prototype uses explicit text.
- Resource and focus results cover one macOS session. Windows fullscreen, Linux Wayland, workspace changes, clicks, and sleep/wake still need manual target-platform testing.
- The adapter currently accepts its credential only from process environment. An OS credential-store launcher would be required before production use.
