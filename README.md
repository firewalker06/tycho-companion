# Tycho Companion

A narrow, runnable macOS 14+ companion for Tycho. It renders a calm SpriteKit coastal workshop at desktop level, controlled from the menu bar and click-through outside explicit Inspect mode. It is a read-only visualizer, not a dashboard or work manager.

## Run locally

Requires Xcode 16 or a Swift 6 toolchain on macOS 14+.

```sh
swift build
swift run TychoCompanion
swift test
```

The first launch uses a bundled synthetic snapshot so no server, credentials, or local configuration is needed. Use **Settings / connection guidance** to learn the safe connection boundary. Live transport accepts only a configured loopback, `.ts.net`, or single-label MagicDNS HTTPS origin and requires a token supplied in memory by the caller; this slice intentionally has no connection form or token persistence.

## Scope and boundaries

- Menu-bar accessory app: no Dock icon, no third-party runtime dependency.
- Transparent borderless window sized from `NSScreen.visibleFrame`, at the public desktop level and below normal windows.
- Ambient mode is non-key and click-through. Inspect is explicit and ends after 15 seconds.
- The client only supports `GET /servers/activity` and `GET /servers/resources`; it never sends mutations or stores activity snapshots.
- The app avoids token/cost/activity-volume cues. A quiet site is healthy.

See [the research report](docs/research/desktop-diorama-visualizer.md) for the product and architecture rationale. This is not an App Store-ready release or a complete MVP.
