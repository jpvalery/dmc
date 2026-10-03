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
| `⌘⌥C` | Swap the browser for the combat tracker, and back |
| `⌘⏎` / `⌘⇧⏎` | Start combat / next turn, and previous turn (tracker only) |
| `⌘[` / `⌘]` / `⌘R` | Back / forward / reload |
| `⌘⇧H` | Campaigns home |
| `⌘⌥1` / `⌘⌥2` | Collapse rail / hide notes |
| `⌘N` | New scene |
| `⌘K` | Command palette: scenes, effects, notes, campaigns, combatants, commands |
| `⌘⌥Z` | Undo the last combat change (tracker only) |
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

### If a file is damaged

A `scenes.json`, `effects.json` or other file that won't read is **copied aside** as
`scenes.corrupt-<time>.json` before anything else happens, and left where it is — an ordinary edit
afterwards can no longer overwrite the only copy. One malformed scene or effect is skipped rather
than taking the rest with it. The rail shows what happened; dismiss it once read.

Good saves of scenes and effects also leave rolling snapshots in the campaign's `backups/` folder
(at most one per ten minutes, the newest thirty kept), so a scene deleted by mistake is a file
copy away. Deleting a note or a campaign moves it to the Trash.

## Audio

Each scene is a set of layers mixed through one `AVAudioEngine`. Files under 60s loop from an
in-memory buffer; longer ones stream in chunks so a 10-minute bed doesn't sit in RAM. Crossfades
are equal-power, so layering doesn't dip through the transition. The engine rebuilds itself on
`AVAudioEngineConfigurationChange`, so switching output devices or waking from sleep recovers.

The scene editor auditions while you edit: moving a gain slider retunes the live mix.

Starting a scene returns at once: its loops are decoded on a background thread (and kept in a
shared cache, so a layer two scenes have in common is decoded once), and the crossfade begins when
they're ready — the outgoing scene keeps playing until then. The scenes either side of the one
playing are decoded ahead of time. A random start offset plays the rest of the file once and then
loops the whole of it, with no second copy of the audio. Fades are timed against the clock.

**Ducking:** an effect can lower the scene's ambience while it sounds (edit the effect:
*Lower the scene while this plays*), then ease it back. Scene layers play through their own
submixer, so the effect itself and the master volume are untouched.

**The knob:** *Next / Previous scene* only moves a dashed **cue** in the rail; the scene that is
cued when the knob stops turning is the one that plays. Spinning past five scenes starts one.

The audio engine stays warm for 45 seconds after the last sound, so the next effect doesn't wait
for the output device to wake, then stops so the app isn't holding it all evening.

## Tabletop Audio

`⌘⇧L` browses the 523-track ambience catalogue, searchable by title, tag and genre, with themed
collections (Dungeon, Dark Forest, Olde Towne, Combat, The Tavern, Castle Raven, DM Tools).
A snapshot ships in the bundle, so the browser works offline and refreshes in the background.

Only the 10-minute ambiences are fetched — those are CC BY-NC-ND 4.0, and credit is written to
`ATTRIBUTION.md` beside the audio. The SoundPad sounds are not downloaded.

A saved SoundPad *layout* can still be imported, from either its JSON or a `ttaud.io` share link:
slot levels and loop flags come across, and each slot is then bound to a file you hold.

## Combat tracker

`⌘⌥C`, or the fencer button in the browser's bar, swaps the centre pane for an initiative
tracker. The web pages stay loaded in their tabs, so closing the tracker returns to D&D Beyond
exactly where it was left.

It is meant for tables that run combat on paper or in their heads rather than in a VTT.

One table, with the same columns from the heading down to the row where new combatants are
entered: type (person or paw), name, HP, AC, Mod (initiative bonus), initiative. The list sorts itself by initiative; ties
keep the order they were added in, and right-click → **Act Earlier / Later** breaks one by hand.
A name, AC and initiative are required to add someone (HP is optional); trying without them
outlines what's missing. A row whose initiative is cleared — as every player's is after End Combat
— is listed at the bottom and takes no turns until it's filled in. HP, AC and initiative commit
on Return or when the field loses focus, not per keystroke, so the list doesn't re-sort mid-edit.

**Start Combat** opens round 1 on the highest initiative; **Next Turn** (`⌘⏎`) advances and opens
a new round when the order wraps. Removing whoever is up passes the turn on rather than skipping
anyone. The `×N` stepper adds a numbered group ("Goblin 1–4") sharing one initiative, AC and
starting HP; each row's HP then moves on its own.

**HP** takes a total (`23`) or just the change: `-7` for damage, `+5` for healing, which stops at
the maximum. The first number typed is the maximum, shown beside it (`13/20`); HP turns orange at
half and red at zero. A player at 0 gets death-save pips (three successes is *stable*, three
failures *dead*); healing clears them.

**Conditions:** the tag button adds Stunned, Concentrating and the rest, optionally *ending after N
turns*. A timed condition counts down as its owner's turn ends and drops off at zero.

**Initiative:** the dice button rolls d20 + the Mod; **⋯ → Roll Initiative for NPCs** rolls every NPC
who hasn't, leaving the party to call out its own. A group (`×N`) shares one initiative by default;
toggle the group icon for each member to roll its own. **⋯ → Add Lair Actions** adds an entry on
initiative 20 that loses every tie.

The magnifier next to the name looks a monster up on [Open5e](https://open5e.com) (the SRD first)
and fills in its name, HP, AC and initiative bonus. Needs a connection; typing the numbers works
without one. **Undo** (header button, or `⌘⌥Z`) steps back through removals, End Combat, clearing,
HP edits and turns.

The person/paw toggle marks a row as a player character or an NPC. Player characters survive
**End Combat** (the red button), which removes the NPCs and clears the party's initiative for the
next fight; their HP and AC are kept. The trash icon clears everyone, and asks for a second
click — it turns into **Confirm clearing** for a few seconds. State is saved per campaign in
`combat.json`, so a relaunch mid-fight comes back to the same turn.

## Notes

Plain markdown, one file per session, lightly styled as you type (headings, **bold**, `code`,
tasks). Write `[[scene:Tavern]]`, `[[effect:Door slam]]` or `[[stop]]` to make a **cue**: `⌘`-click
it while editing, or switch to reading mode (the eye button) where a plain click runs it — so the
prep for a session doubles as its run sheet. The link button inserts one for you. A cue naming
nothing in this campaign is drawn red; a partial name works if it is unambiguous.

Scene starts and combat moments (combat started, each new round, someone dropping to 0 HP, a
condition ending) are appended under a `## Log` heading in today's session note as
`- 20:14 Scene: Tavern`, giving you the recap for free. **View → Log Scenes and Combat to Session
Notes** turns it off.

## Macropad

Global hotkeys via Carbon's `RegisterEventHotKey`, so they work while D&D Beyond has focus and
need no Accessibility permission. F13–F20 are the highest keys macOS has virtual keycodes for, so
reach is extended with modifier banks: bare, Shift, Control and Option — 32 slots.

**Macropad & Hotkeys…** shows the VIA code for each slot and copies the whole mapping to the
clipboard. In VIA, set each key to **Any** and paste the code. A key macOS won't let DMC claim —
another app is using it — is marked with a warning there and noted in the rail.

## Licensing

The MIT licence covers this code. It does not cover `Resources/tta_data.json` (Tabletop Audio's
catalogue metadata) or any audio you download, which stay under their own terms.
