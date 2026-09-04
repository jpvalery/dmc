# Tools

Standalone scripts, deliberately outside `Sources/DMC` so SwiftPM ignores them. The Command Line
Tools toolchain has no `Testing` or `XCTest` module, so verification here is done with plain
executables compiled against the app's sources rather than a test target. Installing Xcode would
allow a real test target instead.

## `mkicon.swift` — app icon

Applies Apple's icon grid (824pt body on a 1024pt canvas, superelliptical corners, contact
shadow) to `Resources/AppIcon.png` and emits an iconset.

```sh
swift Tools/mkicon.swift Resources/AppIcon.png /tmp/AppIcon.iconset
iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
```

## `verify-audio` — engine correctness

Offline-render checks over the audio graph: buffer rotation, gapless looping across the
in-memory and streaming paths, equal-power crossfades, and attach/detach churn under load.
Generates its own test tones into a scratch vault.

```sh
swiftc -O -o /tmp/verify-audio Tools/verify-audio/main.swift \
  Sources/DMC/Models/Vault.swift Sources/DMC/Models/Scene.swift \
  Sources/DMC/Audio/FadeRamp.swift Sources/DMC/Audio/StreamingLooper.swift \
  Sources/DMC/Audio/LayerPlayer.swift \
  -target arm64-apple-macos15 -framework AVFoundation -framework AppKit
/tmp/verify-audio /tmp/dmc-verify-vault
```

## `verify-symbols` — icon names

Checks every SF Symbol in `SceneSymbols.all` against the installed catalogue, so no scene
renders a blank icon.

```sh
swift Tools/verify-symbols/main.swift
```

## `verify-padimport` — SoundPad import

Parses a saved pad (JSON or share link) and confirms levels, loop flags and slot ids survive a
round trip through `scenes.json`.

```sh
mkdir -p /tmp/pad && cp Tools/verify-padimport/main.swift /tmp/pad/
swiftc -O -o /tmp/pad/run /tmp/pad/main.swift \
  Sources/DMC/Models/Vault.swift Sources/DMC/Models/Scene.swift Sources/DMC/Rail/PadImport.swift \
  -target arm64-apple-macos15 -framework AppKit -framework SwiftUI
/tmp/pad/run <path-to-pad.json>
```
