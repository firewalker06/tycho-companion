# Tycho Companion

A narrow Godot 4 desktop diorama for Tycho. It is a quiet read-only visualizer, not a dashboard or work manager.

## Run and export

Use Godot 4.7.2 (standard, non-.NET). Open `godot/project.godot` in the editor and run it, or use the command line:

```sh
godot --path godot --editor
GODOT_BIN=godot ./scripts/export_windows.sh
cd dist/windows-x86_64 && zip -q ../TychoCompanion-windows-x86_64.zip TychoCompanion.exe
```

The export script forces Godot's image import scan before packaging; this prevents fresh checkouts from producing a build whose tracked `.png.import` metadata points at missing cached textures.

The tracked project starts as an empty shoreline and needs no server or credentials. Open **Settings** in the strip to connect a loopback, single-label MagicDNS, or `.ts.net` HTTPS Tycho origin. On Windows, DPAPI encrypts the saved token for the current Windows account, cryptographically binds it to that exact origin, and lets later builds reuse it from the stable `Tycho Companion` user-data directory. Changing origins requires a token, preventing one server's credential from reaching another. **Disconnect** removes the saved token; quitting preserves it. Plaintext tokens are never written to the config file or included in logs and diagnostics. `TYCHO_ORIGIN` and `TYCHO_TOKEN` form one atomic environment pair for an initial live connection; a missing or unsafe half rejects both rather than combining either with persisted state. A valid environment credential remains transient unless the operator explicitly connects through Settings. The client issues only authenticated `GET /servers/activity` and `GET /servers/resources` requests.

Open **Debug** to probe both endpoints, switch between live rendering and a deterministic nine-state fixture, or save a clean compact PNG. The same render/snapshot smoke path is available from the command line without credentials:

```sh
godot --path godot -- --debug-render-snapshot
godot --headless --path godot -- --debug-render-check
```

Both flags bypass saved configuration, environment credentials, and network startup before `ConnectionClient` initializes. Snapshot capture needs a real rendering driver; the headless check validates the synthetic fixture and asset regions without reading a viewport texture.

When a configured connection fails, the strip reports the real retrying state and preserves only the last live scene as stale; it never substitutes demo activity. Disconnect clears both the in-memory and saved token and returns to the empty shoreline. Failed attempts back off exponentially from 2 seconds with a cap; after attempt 3 the client enters explicit offline state until manually reconnected. Stale request completions are discarded after a reconnect or disconnect.

The Windows attachment is an unsigned x86_64 test build. Extract it and run `TychoCompanion.exe`; Windows may show a SmartScreen warning because this is not a signed release.

## Scope

- Project-owned 2048 px transparent coastal-workshop cutout and caretaker atlas on an explicit ambient CanvasLayer. The workshop keeps its aspect ratio and contains only the pier, three work bays, and their objects. Active caretaker poses have restrained state-specific motion; stopped, stale, and offline poses freeze and disable continuous processing when no other active pose remains.
- Calm state semantics for idle, running, awaiting input, blocked, success, failure, partial, stopped, unread, and stale/offline.
- Borderless, transparent, bottom-edge window with Settings, Inspect, Debug, and **Save & Quit** controls. Save & Quit and the native window-close request synchronously preserve the protected token before exiting; if that save fails, the app remains open and reports the error. `I` toggles Inspect and `Esc` closes overlays. The 2048 px art is rendered into a 300 px bottom strip; Settings (528 px), Inspect (578 px), or Debug (578 px) add an above-strip panel while the native bottom edge remains fixed, then close back to 300 px.
- Debug tools probe both read-only Tycho endpoints without changing live polling, validate and preview all lifecycle poses with synthetic data, and save clean compact PNG snapshots under the platform-specific `user://snapshots` directory. Raw activity and resources bodies stay inside the transport; the scene signal carries only sanitized lifecycle/display fields and a refresh time. Debug reports never include tokens or response bodies.
- On Windows, Godot uses the mouse-passthrough polygon as the native paint region. The app therefore includes the whole painted strip in that region so the workshop remains visible; the 300 px strip and an open overlay intercept clicks. Other platforms keep the narrower control-only input region. True cross-process click-through on Windows requires native window integration that this dependency-free prototype does not include.
- Windows behavior is a test target, not a promise of full macOS desktop-level or menu-bar parity. Native macOS lifecycle and Keychain integration are deferred.

See [the research report](docs/research/desktop-diorama-visualizer.md) for the architecture rationale. This is not an App Store-ready release or a complete MVP.

Asset provenance, tracked dimensions, atlas layout, processing notes, and hashes are in [godot/assets/README.md](godot/assets/README.md).

## Verification

Verification covers a normal runtime launch, source and caretaker-atlas inspection, all deterministic headless suites, the credential-free diagnostic, a Godot 4.7.2 Windows export, ZIP integrity, privacy/debug-marker scans, and `git diff --check`. The built-in snapshot tool captures the Godot viewport directly, avoiding desktop-layer screenshot ambiguity.
