# Windows test build

Extract the attached ZIP, then run `TychoCompanion.exe`.

This is a portable x86_64 test build using the Godot 4.7.2 Windows runtime. It starts with a packed local demo. Use **Settings** to enter a safe Tycho origin and a bearer token; the token remains in memory and only read-only activity/resources requests are made. **Inspect** shows connection diagnostics and mapped agent states; **Quit** exits cleanly.

On transparent Windows builds, only the compact controls and an open overlay receive pointer input. Godot's explicit mouse-passthrough polygon forwards clicks over all ambient scene pixels to the desktop.

It is not signed as Tycho Companion, so Windows SmartScreen may ask for confirmation. Do not use it as a production install.
