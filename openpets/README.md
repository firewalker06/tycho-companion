# OpenPets comparison prototype

This directory implements Fizzy #160 as a standalone OpenPets SDK v3 plugin and a loopback-only Tycho adapter. It does not fork OpenPets, patch OpenPets core, or modify the merged Godot baseline.

The adapter is the only component that reads the Tycho origin and bearer credential. It makes authenticated `GET /servers/activity` requests, converts each `(server_key, agent_key)` pair to a persisted opaque UUID, and serves only bounded lifecycle flags and numeric counts from `http://127.0.0.1:7737/snapshot`. The plugin never receives an origin, credential, display name, project key, prompt, summary, filesystem path, log, conversation, or usage value.

## Prerequisites

- Node.js 20 or newer.
- OpenPets built from commit `6c8187c4b67d4e27c6e4e573530bd74b5e998c75`, or another SDK v3 build whose manifest validator and network bridge support `network:local`.
- At least one non-built-in OpenPets pet package installed. The default plugin setting uses `snoopy` for spawned windows.

The published `@open-pets/cli` 3.3.0 package predates `network:local` and rejects this manifest. The validator and runtime at the pinned source commit accept it. Treat this as a prototype compatibility limit, not a reason to remove the local-network permission.

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

The adapter keeps lifecycle, server health, and unread independent. Running is active but does not demand attention. Awaiting input, blocked, terminal, stale, offline, and unread states set attention without rewriting lifecycle. A successful valid snapshot removes archived or absent agents; transport failure preserves the last valid entities as offline.

The plugin persists only opaque UUID-to-pet-package/slot assignments and the last sanitized state. It updates a pet in place across reruns, terminal states, and stale snapshots. A valid snapshot that removes an entity releases its bubble and spawned window. Repeated revisions and plugin/adapter restarts restore persistent cues but do not replay terminal or unread reactions.

Disable or unload the plugin before stopping OpenPets. Its explicit cleanup cancels polling, unregisters the refresh command, dismisses bubbles, clears status reactions, and closes every spawned pet. Stop the adapter separately. Delete its assignment-state file only if intentionally resetting stable identities.

## Verification

```sh
cd openpets
npm test
npm run benchmark
/usr/bin/time -lp node adapter/idle-resource-check.mjs
```

The tests use the official `@open-pets/plugin-sdk/testing` harness and a real loopback HTTP server. They cover the five-pet cap, overflow, same-package and distinct-package spawns, lifecycle/attention/unread recognition, stable update/release, rerun, terminal, stale, archive, repeated snapshots, adapter and plugin restarts, transport loss, private assignment persistence, and cleanup.

See [the comparison evidence](../docs/openpets-comparison-prototype.md) for measured results and limitations.
