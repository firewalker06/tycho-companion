# ADR 0001: Use Godot for the Windows prototype

The research report recommends AppKit plus SpriteKit for the macOS-first product. The user has chosen Godot 4 for this prototype so it can be tested on Windows. This decision overrides the engine recommendation for the current branch, not the report's product, privacy, or state-semantics guidance.

The project uses standard Godot 4.7.2 with GDScript and the Compatibility renderer. It has no add-ons or external art assets. The Windows test ZIP is portable, not an installer or signed Tycho release. It packages the Godot Windows runtime with a packed, synthetic scene; it makes no network requests.

This deliberately defers native macOS details from the report: accessory/menu-bar behavior, public desktop-level placement, Keychain, and AppKit accessibility elements. If Windows testing validates the scene, choose whether to invest in Godot platform adapters or return to a native macOS host before adding live credentials or polling.
