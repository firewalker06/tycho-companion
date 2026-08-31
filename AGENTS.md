# Tycho Companion

- Target macOS 14+ with AppKit and SpriteKit; keep the app dependency-free.
- Treat `docs/research/desktop-diorama-visualizer.md` as the architecture source of truth.
- Never add live Tycho data, origins, tokens, logs, or local configuration to this public repository.
- Keep networking read-only and scene models free of prompts, summaries, filesystem paths, and usage metrics.
- Run `swift build`, `swift test`, and `git diff --check` before handing off changes.
