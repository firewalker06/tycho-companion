# Tycho Companion

A narrow Godot 4 desktop diorama for Tycho. It is a quiet read-only visualizer, not a dashboard or work manager.

## Run and export

Use Godot 4.7.2 (standard, non-.NET). Open `godot/project.godot` in the editor and run it, or use the command line:

```sh
godot --path godot --editor
godot --path godot --headless --export-release "Windows Desktop" ../dist/TychoCompanion.exe
```

The tracked project ships a synthetic demo only, so it needs no server, credentials, or local configuration. The live-client boundary remains deliberately unimplemented: a future slice may accept only a configured loopback, `.ts.net`, or MagicDNS HTTPS origin, retain a token in OS secure storage, and issue only `GET /servers/activity` and `GET /servers/resources`.

The Windows attachment is an unsigned x86_64 test build. Extract it and run `TychoCompanion.exe`; Windows may show a SmartScreen warning because this is not a signed release.

## Scope

- Procedural coastal-workshop scene with no external art assets or add-ons.
- Calm state semantics for idle, running, awaiting input, blocked, success, failure, partial, stopped, unread, and stale/offline.
- Borderless, transparent, bottom-edge window; `I` enters temporary Inspect mode and `Esc` exits.
- Windows behavior is a test target, not a promise of full macOS desktop-level or menu-bar parity. Native macOS lifecycle and Keychain integration are deferred.

See [the research report](docs/research/desktop-diorama-visualizer.md) for the architecture rationale. This is not an App Store-ready release or a complete MVP.
