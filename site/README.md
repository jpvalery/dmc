# DMC website

One page, built with Astro and Tailwind CSS v4. The look is "Headliner": a screen-printed gig
poster in bone, brass and blood red on plum black, with New Rocker for headings, Grenze for text
and DM Mono for labels and keys. Fonts are self-hosted through Fontsource.

```sh
npm install
npm run dev      # http://localhost:4321
npm run build    # static output in dist/
```

## Where things are

| Path | What it holds |
|---|---|
| `src/styles/global.css` | Tailwind theme tokens (colours, fonts) and the few custom utilities |
| `src/data/content.ts` | Feature list, sound sources, FAQ and gallery captions |
| `src/lib/release.ts` | Reads the latest GitHub release at build time: version, DMG size, links |
| `src/components/` | One component per section, plus `Button`, `Section`, `Sketch` and `PadBlueprint` |
| `src/assets/screenshots/` | App screenshots, picked up by file name (see below) |
| `og/og.html` | Source of `public/og.png`, the link preview |
| `screenshots/make-demo-vault.py` | Writes the demo campaign the screenshots are taken from |

The download buttons point to `releases/latest/download/DMC.dmg`, so a new release needs no site
change. The release workflow redeploys the site through a Vercel deploy hook so the version and
size shown on the page stay current.

## Deploying on Vercel

Import the repository in Vercel and set **Root Directory** to `site`. Vercel detects Astro, and
the defaults (`npm run build`, output `dist`) are right. Keep "Include files outside the root
directory" on: the build falls back to `app/Resources/Info.plist` for the version when GitHub's
API is unavailable.

Optional:
- `SITE_URL`: the custom domain, once there is one (for canonical and Open Graph URLs).
- `GITHUB_TOKEN`: raises the GitHub API rate limit for the release lookup.
- Create a deploy hook (Settings → Git → Deploy Hooks) and save its URL as the
  `VERCEL_DEPLOY_HOOK` secret in the GitHub repository.

## Screenshots

Until the real shots exist, the hero and gallery show line sketches (`Sketch.astro`). Dropping a
PNG into `src/assets/screenshots/` replaces its sketch at the next build:

| File | Shot |
|---|---|
| `main.png` | Full window: a scene playing, a D&D Beyond monster page, Session 12's note |
| `scene-editor.png` | The scene editor on Tavern, with a sporadic layer |
| `combat.png` | The combat tracker, round 3 |
| `notes.png` | Notes in reading mode, with cues and the log |
| `tabletop.png` | The Tabletop Audio browser (⌘⇧L) |
| `palette.png` | The ⌘K palette over the main window |
| `pad-mapper.png` | Macropad & Hotkeys (optional) |

The gallery shows full rows of three only, so it needs three or six of the last six.

To take them without touching a real vault or settings:

1. `python3 screenshots/make-demo-vault.py /tmp/dmc-demo/vault` writes the demo campaign and
   copies the audio it uses from `~/DMConsole/audio`.
2. Copy `app/build/DMC.app` to `/tmp/dmc-demo/DMC Demo.app`, set its bundle identifier to
   `me.jpvalery.dmc.demo` with PlistBuddy, and re-sign it ad hoc. Its own identifier keeps its
   preferences and its D&D Beyond cookies apart from the real app.
3. Point it at the vault and quiet it down:
   ```sh
   D=me.jpvalery.dmc.demo
   defaults write $D vault.path /tmp/dmc-demo/vault
   defaults write $D log.enabled -bool false
   defaults write $D audio.masterVolume -float 0.1
   ```
   `pane.combatShown` and `notes.readMode` (both `-bool true`) open straight into the combat and
   reading-mode shots.
4. Size the window to about 1440×900 points and capture it with `screencapture -x -o -l <window id>`.
   The terminal needs Screen Recording access for that (and Accessibility, to drive the app).
5. `defaults delete me.jpvalery.dmc.demo` when done.

## Link preview

`public/og.png` is rendered from `og/og.html`. Serve this folder (`python3 -m http.server -d .`),
open `/og/og.html` at 1200×630 and save the capture over `public/og.png`.
