# Windows test build

Extract the attached ZIP, then run `TychoCompanion.exe`.

This is a portable x86_64 test build using the Godot 4.7.2 Windows runtime. It starts as an empty shoreline. Use **Settings** to enter a safe Tycho origin and a bearer token; Windows DPAPI encrypts the saved token for the current Windows account and binds it to that exact origin, so later builds reconnect without asking for it again. Changing origins requires a token. `TYCHO_ORIGIN` and `TYCHO_TOKEN` are accepted only as one complete, safe environment pair. **Disconnect** removes the saved token and reports any removal failure. Only read-only activity/resources requests are made. **Inspect** shows connection diagnostics and mapped agent states. **Debug** can probe both endpoints, preview a deterministic nine-state render fixture, and save a clean PNG under the Godot application-data directory. **Save & Quit** and the native close request preserve the token before exiting. If Windows cannot complete that save, the app remains open and reports the error.

Raw activity and resources responses remain inside the transport layer. Only sanitized caretaker lifecycle/display fields and the refresh time cross into the scene. Credential-free command-line diagnostics bypass saved configuration, environment credentials, and HTTP startup before the connection client initializes.

On Windows, Godot couples its mouse-passthrough polygon to the native paint region. The whole painted 300 px strip must therefore receive pointer input or Windows clips it away; an open overlay receives input too. True cross-process click-through needs a native Windows adapter and is outside this dependency-free prototype.

The compact strip is always the bottom-most 300 px and remains attached to the usable desktop bottom edge. Opening Settings grows the transparent window to 528 px; Inspect or Debug grows it to 578 px. Closing the overlay restores the 300 px footprint.

It is not signed as Tycho Companion, so Windows SmartScreen may ask for confirmation. Do not use it as a production install.
