# DMC

A single-window macOS app for running D&D sessions, replacing a pile of browser tabs with three
panes: a scene rail for layered ambient audio, a webview for D&D Beyond, and a notepad.

Native Swift/SwiftUI, no Electron. Built for an M4 MacBook Air.

## Building

Needs the Xcode Command Line Tools; Xcode itself is not required.

```sh
make bundle     # builds and assembles build/DMC.app
make run        # bundle, then launch
make install    # copy to /Applications
```

The bundle is ad-hoc signed, so the first launch needs right-click → Open.

## Layout

| Pane | Default width | What it is |
|---|---|---|
| Scene rail | 1/8 | Icon per scene; click to fade in, click again to fade out |
| Web | 4/8 | D&D Beyond, with tabs and an optional side-by-side split |
| Notes | 3/8 | Per-campaign markdown |

Both side panes collapse. The rail keeps its icons when collapsed so scenes stay one click away.

## Shortcuts

| Keys | Action |
|---|---|
| `⌘1`–`⌘9` | Toggle the first nine scenes |
| `⌘0` | Stop all audio |
| `⌘T` / `⌘W` | New tab / close tab |
| `⌃Tab` / `⌃⇧Tab` | Next / previous tab |
| `⌘⌥S` | Split side by side |
| `⌘[` / `⌘]` / `⌘R` | Back / forward / reload |
| `⌘⇧H` | Campaigns home |
| `⌘⌥1` / `⌘⌥2` | Collapse rail / hide notes |
| `⌘N` | New scene |
| `⌘⇧L` | Browse Tabletop Audio |

`⌘\` is deliberately left unbound so 1Password's Universal Autofill reaches the focused field.

⌘-click opens a link in a background tab; right-click offers "Open Link in New Tab".

## The vault

Everything lives in `~/DMConsole` (overridable with the `vault.path` user default):

```
~/DMConsole/
├── audio/              # any folder here becomes a scene, if scenes.json is absent
│   └── Tabletop Audio/ # downloads land here, with ATTRIBUTION.md
├── notes/
├── scenes.json         # authoritative once you save a scene
└── library.json        # duration cache
```

Saving a scene creates `scenes.json`, which switches off the folder-per-scene convention.
**Import Folders as Scenes** brings it back on demand.

## Audio

Each scene is a set of layers mixed through one `AVAudioEngine`. Files under 60s loop from an
in-memory buffer; longer ones stream in chunks so a 10-minute bed doesn't sit in RAM. Crossfades
are equal-power, so layering doesn't dip through the transition. The engine rebuilds itself on
`AVAudioEngineConfigurationChange`, so switching output devices or waking from sleep recovers.

The scene editor auditions while you edit: moving a gain slider retunes the live mix.

## Tabletop Audio

`⌘⇧L` browses the 523-track ambience catalogue, searchable by title, tag and genre, with themed
collections (Dungeon, Dark Forest, Olde Towne, Combat, The Tavern, Castle Raven, DM Tools).
A snapshot ships in the bundle, so the browser works offline and refreshes in the background.

Only the 10-minute ambiences are fetched — those are CC BY-NC-ND 4.0, and credit is written to
`ATTRIBUTION.md` beside the audio. The SoundPad sounds are not downloaded.

A saved SoundPad *layout* can still be imported, from either its JSON or a `ttaud.io` share link:
slot levels and loop flags come across, and each slot is then bound to a file you hold.

## Macropad

Global hotkeys via Carbon's `RegisterEventHotKey`, so they work while D&D Beyond has focus and
need no Accessibility permission. F13–F20 are the highest keys macOS has virtual keycodes for, so
reach is extended with modifier banks: bare, Shift, Control and Option — 32 slots.

**Macropad & Hotkeys…** shows the VIA code for each slot and copies the whole mapping to the
clipboard. In VIA, set each key to **Any** and paste the code.

## Licensing

The MIT licence covers this code. It does not cover `Resources/tta_data.json` (Tabletop Audio's
catalogue metadata) or any audio you download, which stay under their own terms.
