# Tycho Companion

A narrow Godot 4 desktop diorama for Tycho. It is a quiet read-only visualizer, not a dashboard or work manager.

## Run and export

Use Godot 4.7.2 (standard, non-.NET). Open `godot/project.godot` in the editor and run it, or use the command line:

```sh
godot --path godot --editor
godot --path godot --headless --export-release "Windows Desktop" ../dist/windows-x86_64/TychoCompanion.exe
cd dist/windows-x86_64 && zip -q ../TychoCompanion-windows-x86_64.zip TychoCompanion.exe
```

The tracked project starts as an empty shoreline and needs no server or credentials. Open **Settings** in the strip to connect a loopback, single-label MagicDNS, or `.ts.net` HTTPS Tycho origin. The bearer token stays in memory only; only the validated origin may be saved under `user://`. `TYCHO_ORIGIN` and `TYCHO_TOKEN` can provide an initial live connection without being logged. The client issues only authenticated `GET /servers/activity` and `GET /servers/resources` requests.

When a configured connection fails, the strip reports the real retrying state and preserves only the last live scene as stale; it never substitutes demo activity. Disconnect clears the token and returns to the empty shoreline. Retries back off from 2 seconds to a capped 60 seconds, and stale request completions are discarded after a reconnect or disconnect.

The Windows attachment is an unsigned x86_64 test build. Extract it and run `TychoCompanion.exe`; Windows may show a SmartScreen warning because this is not a signed release.

## Scope

- Project-owned coastal-workshop and caretaker-atlas art. The documented source crop keeps all three work bays visible without letterboxing; caretaker poses map directly to lifecycle state.
- Calm state semantics for idle, running, awaiting input, blocked, success, failure, partial, stopped, unread, and stale/offline.
- Borderless, transparent, bottom-edge window with Settings, Inspect, and Quit controls. `I` toggles Inspect and `Esc` closes overlays. The compact footprint is 160 px high; an open Settings (276 px) or Inspect (326 px) overlay expands upward while its bottom edge remains attached to the usable desktop edge, then closes back to 160 px.
- On Windows, an explicit Godot mouse-passthrough polygon accepts input only over the compact control/overlay rectangle; ambient scene pixels pass through to the desktop.
- Windows behavior is a test target, not a promise of full macOS desktop-level or menu-bar parity. Native macOS lifecycle and Keychain integration are deferred.

See [the research report](docs/research/desktop-diorama-visualizer.md) for the architecture rationale. This is not an App Store-ready release or a complete MVP.

Asset provenance and exact source dimensions, crop, atlas layout, and hashes are in [godot/assets/README.md](godot/assets/README.md).
