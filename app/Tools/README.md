# Tools

Standalone scripts, deliberately outside `Sources/DMC` so SwiftPM ignores them. The Command Line
Tools toolchain has no `Testing` or `XCTest` module, so verification here is done with plain
executables compiled against the app's sources rather than a test target. Installing Xcode would
allow a real test target instead.

The commands below use paths relative to `app/`, so run them from there.

## `mkicon.swift` — app icon

Applies Apple's icon grid (824pt body on a 1024pt canvas, superelliptical corners, contact
shadow) to `Resources/AppIcon.png` and emits an iconset.

```sh
swift Tools/mkicon.swift Resources/AppIcon.png /tmp/AppIcon.iconset
iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
```

## `verify-audio` — engine correctness

Offline-render checks over the audio graph: a random start (lead-in, then the loop) reproducing
the file sample for sample, gapless looping across the in-memory and streaming paths, the
decoded-buffer cache, equal-power crossfades, fades that follow the clock rather than counting
steps, ducking through the bed fader, and attach/detach churn under load. Generates its own test
tones into a scratch vault the first time it runs.

```sh
swiftc -O -swift-version 5 -o /tmp/verify-audio Tools/verify-audio/main.swift \
  Sources/DMC/Models/Vault.swift Sources/DMC/Models/Campaign.swift Sources/DMC/Models/Scene.swift \
  Sources/DMC/Support/JSONStore.swift Sources/DMC/Support/Diagnostics.swift \
  Sources/DMC/Audio/FadeRamp.swift Sources/DMC/Audio/StreamingLooper.swift \
  Sources/DMC/Audio/LayerPlayer.swift Sources/DMC/Audio/BufferCache.swift \
  -target arm64-apple-macos15 -framework AVFoundation -framework AppKit
/tmp/verify-audio /tmp/dmc-verify-vault
```

## `verify-symbols` — icon names

Checks every SF Symbol in `SceneSymbols.all` against the installed catalogue, so no scene
renders a blank icon.

```sh
swift Tools/verify-symbols/main.swift
```

## `verify-notes` — notepad persistence

Exercises the session store headlessly: today's session, debounced autosave with no explicit
save, survival across a simulated force-quit, switching between sessions without losing an
in-flight edit, renaming while keeping the date prefix, the session log (heading creation,
ordering, writing to today's file while another note is open), and `[[scene:…]]` cue parsing and
matching.

```sh
mkdir -p /tmp/nv && cp Tools/verify-notes/main.swift /tmp/nv/
swiftc -O -parse-as-library -swift-version 5 -o /tmp/nv/run /tmp/nv/main.swift \
  Sources/DMC/Models/Vault.swift Sources/DMC/Models/Campaign.swift \
  Sources/DMC/Notes/NotesStore.swift Sources/DMC/Notes/NoteLinks.swift \
  Sources/DMC/Support/JSONStore.swift Sources/DMC/Support/Diagnostics.swift \
  -target arm64-apple-macos15 -framework AppKit
/tmp/nv/run /tmp/nv/vault
```

## `verify-combat` — combat tracker

Initiative order and tie-breaking, HP and AC, round and turn advancement, removing or
un-rolling whoever is up, ending a fight while keeping the party, and persistence across a
simulated relaunch — including a sparse file and one whose turn points at nobody. Also `-7` / `+5`
HP entry with a maximum and bloodied state, death saves, conditions counting down as their
owner's turn ends, undo, lair actions losing ties, and rolling initiative singly and per group.
Also the four-step health scale, condition icons (checked against the installed SF Symbols), and
prepared encounters: loading one beside the party, the start hook that carries its scene, marking
it done on ending, undo, and persistence.

```sh
mkdir -p /tmp/cv && cp Tools/verify-combat/main.swift /tmp/cv/
swiftc -O -parse-as-library -swift-version 5 -o /tmp/cv/run /tmp/cv/main.swift \
  Sources/DMC/Models/Vault.swift Sources/DMC/Models/Campaign.swift \
  Sources/DMC/Models/Combat.swift \
  Sources/DMC/Support/JSONStore.swift Sources/DMC/Support/Diagnostics.swift \
  -target arm64-apple-macos15 -framework AppKit
/tmp/cv/run /tmp/cv/vault
```

## `verify-padimport` — SoundPad import

Parses a saved pad (JSON or share link) and confirms levels, loop flags and slot ids survive a
round trip through `scenes.json`.

```sh
mkdir -p /tmp/pad && cp Tools/verify-padimport/main.swift /tmp/pad/
swiftc -O -o /tmp/pad/run /tmp/pad/main.swift \
  Sources/DMC/Models/Vault.swift Sources/DMC/Models/Campaign.swift Sources/DMC/Models/Scene.swift \
  Sources/DMC/Rail/PadImport.swift \
  Sources/DMC/Support/JSONStore.swift Sources/DMC/Support/Diagnostics.swift \
  -target arm64-apple-macos15 -framework AppKit -framework SwiftUI
/tmp/pad/run <path-to-pad.json>
```

## `verify-persistence` — damaged files, backups, snapshots

The bug this keeps fixed: a `scenes.json` that failed to decode was treated as empty, so the first
ordinary edit wrote the empty state back over it. Replays that against the real `SceneStore` and
`EffectStore`: a damaged file is copied aside byte for byte and left in place, an edit afterwards
cannot destroy the copy, the same damage is not backed up twice, one bad scene does not take the
others with it, good saves leave rolling snapshots (at most one per ten minutes), and a failed
write is reported.

```sh
mkdir -p /tmp/pv && cp Tools/verify-persistence/main.swift /tmp/pv/
swiftc -O -parse-as-library -swift-version 5 -o /tmp/pv/run /tmp/pv/main.swift \
  Sources/DMC/Models/Vault.swift Sources/DMC/Models/Campaign.swift Sources/DMC/Models/Scene.swift \
  Sources/DMC/Models/SceneStore.swift Sources/DMC/Models/Effect.swift \
  Sources/DMC/Support/JSONStore.swift Sources/DMC/Support/Diagnostics.swift \
  -target arm64-apple-macos15 -framework AppKit -framework SwiftUI
rm -rf /tmp/pv/vault && /tmp/pv/run /tmp/pv/vault
```

## `verify-engine` — scheduling against a real audio engine

Drives `SceneEngine` and `SceneCue` with the master volume at zero, so it is silent: playing
returns at once and the sound follows, of two quick requests only the last starts, a scene
stopped before it was ready never starts, a missing file is reported without stopping the rest, an
edit restarts quietly, effects finish and are forgotten, and turning the knob through several
scenes plays only the one it stops on. Needs an audio output device.

```sh
mkdir -p /tmp/ee && cp Tools/verify-engine/main.swift /tmp/ee/
swiftc -O -parse-as-library -swift-version 5 -o /tmp/ee/run /tmp/ee/main.swift \
  Sources/DMC/Models/Vault.swift Sources/DMC/Models/Campaign.swift Sources/DMC/Models/Scene.swift \
  Sources/DMC/Models/Effect.swift \
  Sources/DMC/Support/JSONStore.swift Sources/DMC/Support/Diagnostics.swift \
  Sources/DMC/Audio/FadeRamp.swift Sources/DMC/Audio/StreamingLooper.swift \
  Sources/DMC/Audio/LayerPlayer.swift Sources/DMC/Audio/BufferCache.swift \
  Sources/DMC/Audio/SceneEngine.swift Sources/DMC/Audio/SceneCue.swift \
  -target arm64-apple-macos15 -framework AVFoundation -framework AppKit
rm -rf /tmp/ee/vault && /tmp/ee/run /tmp/ee/vault
```

## `verify-editor` — the notepad's text view

Builds the real text view in an offscreen window: headings, bold, code and tasks are styled, a
`[[scene:…]]` cue is live only when it names something that exists, the text on disk is never
changed by styling, ⌘-click (or a plain click in reading mode) fires a cue, and a click in blank
space, the margin or on a broken cue does not.

```sh
mkdir -p /tmp/ev && cp Tools/verify-editor/main.swift /tmp/ev/
swiftc -O -parse-as-library -swift-version 5 -o /tmp/ev/run /tmp/ev/main.swift \
  Sources/DMC/Models/Vault.swift Sources/DMC/Models/Campaign.swift \
  Sources/DMC/Notes/NotesStore.swift Sources/DMC/Notes/NoteLinks.swift Sources/DMC/Notes/MarkdownEditor.swift \
  Sources/DMC/Support/JSONStore.swift Sources/DMC/Support/Diagnostics.swift \
  -target arm64-apple-macos15 -framework AppKit -framework SwiftUI
rm -rf /tmp/ev/vault && /tmp/ev/run /tmp/ev/vault
```

## `verify-web` — restoring tabs

Restores three tabs from a saved list using local pages: only the first loads at launch, the
others show their address and load when first shown, and saving while they are unloaded keeps all
of them.

```sh
mkdir -p /tmp/wv && cp Tools/verify-web/main.swift /tmp/wv/
swiftc -O -parse-as-library -swift-version 5 -o /tmp/wv/run /tmp/wv/main.swift \
  Sources/DMC/Models/Vault.swift Sources/DMC/Models/Campaign.swift \
  Sources/DMC/Support/JSONStore.swift Sources/DMC/Support/Diagnostics.swift \
  Sources/DMC/Web/WebController.swift Sources/DMC/Web/WebTabs.swift \
  -target arm64-apple-macos15 -framework AppKit -framework SwiftUI -framework WebKit
rm -rf /tmp/wv/vault && mkdir -p /tmp/wv/vault && /tmp/wv/run /tmp/wv/vault
```
