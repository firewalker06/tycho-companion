# OpenPets comparison prototype

This directory implements Fizzy #160 as a standalone OpenPets SDK v3 plugin and a loopback-only Tycho adapter. It does not fork OpenPets, patch OpenPets core, or modify the merged Godot baseline.

The adapter is the only component that reads the Tycho origin and bearer credential. It makes authenticated `GET /servers/activity` requests, converts each `(server_key, agent_key)` pair to a persisted opaque UUID, and serves only bounded lifecycle flags and numeric counts from `http://127.0.0.1:7737/snapshot`. The plugin never receives an origin, credential, display name, project key, prompt, summary, filesystem path, log, conversation, or usage value.

## Prerequisites

- Node.js 20 or newer.
- OpenPets built from commit `6c8187c4b67d4e27c6e4e573530bd74b5e998c75`, or another SDK v3 build whose manifest validator and network bridge support `network:local`.
- At least one non-built-in OpenPets pet package installed. The default plugin setting uses `snoopy` for spawned windows.

The test harness is pinned exactly to `@open-pets/plugin-sdk` 3.3.0. The published `@open-pets/cli` 3.3.0 package predates `network:local` and rejects this manifest; the CLI and desktop validators built from the research-pinned source commit accept it. Treat the published-package mismatch as a prototype compatibility limit, not a reason to remove the local-network permission.

## Setup

Install the test-only SDK dependency:

```sh
cd openpets
npm ci --ignore-scripts
```

Set `TYCHO_ORIGIN` and `TYCHO_TOKEN` in the adapter process environment using a private shell or process manager, then start the adapter:

```sh
node adapter/tycho-loopback-adapter.mjs
```

Do not put the credential in an OpenPets config field, command argument, checked-in file, service log, or shell history. `TYCHO_OPENPETS_STATE_FILE` may override the assignment-state location; the default is under the user's state directory. The file is created with mode `0600`, stores only SHA-256 identity digests mapped to random UUIDs, and is replaced atomically.

In OpenPets, enable Developer Mode and load `openpets/plugin` as an unpacked plugin. Approve only its declared fixed loopback host and capabilities. The `petPackageIds` setting accepts comma-separated installed package IDs:

- `snoopy` spawns four instances from the same package.
- `snoopy,tux,wall-e,clippit` gives the four spawned slots distinct packages.

OpenPets SDK v3 limits a plugin to four spawned pets. This prototype uses the existing default pet as slot one and four spawned pets as slots two through five. Higher-priority entities remain visible; the plugin status reports an explicit `+N overflow` for the rest.

## State behavior

The adapter validates the complete server and agent arrays, including every lifecycle and current Tycho server status, before allocating or removing an assignment. One malformed row rejects the whole snapshot and preserves the last valid model and assignment store. `loading` maps to stale attention; `unauthorized` maps to offline attention. Running is active but does not demand attention. Awaiting input, blocked, terminal, stale, offline, and unread states set attention without rewriting lifecycle.

The plugin persists only `assignment_revision` and opaque UUID-to-pet-package/slot assignments. Source revision, lifecycle, active, attention, unread, health, and transition history remain in the captured runtime instance and are discarded on unload. It updates a pet in place across reruns, terminal states, and stale snapshots. A valid snapshot that removes an entity releases its bubble and spawned window. Repeated revisions do not replay terminal or unread reactions; a restart restores cosmetic assignments and renders the first snapshot without a one-shot transition.

The adapter halts automatic Tycho requests after the first confirmed HTTP 401. Restart it or call its in-process `reconfigure` seam with a complete safe origin/credential pair to resume. Network, 5xx, timeout, malformed, and oversized responses use deterministic exponential delays of 5, 10, 20, 40, then at most 60 seconds. The plugin independently backs off its loopback requests from 10 seconds to the same 60-second cap.

Disable or unload the plugin before stopping OpenPets. Its explicit cleanup cancels polling, unregisters the refresh command, dismisses bubbles, clears status reactions, and closes every spawned pet. Stop the adapter separately. Delete its assignment-state file only if intentionally resetting stable identities.

## Verification

```sh
cd openpets
npm test
npm run benchmark
/usr/bin/time -lp node adapter/idle-resource-check.mjs
```

The 23 tests use the pinned official `@open-pets/plugin-sdk/testing` 3.3.0 harness and a real loopback HTTP server. They cover the five-pet cap, overflow, same-package and distinct-package spawns, lifecycle/attention/unread recognition, partial cues, stable update/release, rerun, terminal, stale, archive, repeated snapshots, adapter and plugin restarts, legacy-state migration, atomic malformed-row rejection, loading/unauthorized mapping, 401 latching, deterministic backoff, private cosmetic-only persistence, delayed-fetch unload, and cleanup.

For the non-empty pinned-desktop check, run `npm run fixture:real-host` beside the pinned desktop with `OPENPETS_DEV_PLUGIN_PATHS` set to this plugin. The synthetic fixture exposes two running entities, changes both to partial, then removes both. A temporary installed test pet is required to exercise the spawned-window path; do not reuse a real OpenPets profile. The recorded run created two assignments, emitted one host-counted `waiting` reaction after the update, returned to zero assignments after release, and left the plugin enabled and unbroken with no SDK dispatch failure.

See [the comparison evidence](../docs/openpets-comparison-prototype.md) for measured results and limitations.
