# DMC

**Dungeon Master of Ceremonies.** A free macOS app for running D&D sessions from one window:
layered soundscapes, D&D Beyond, a combat tracker and notes, side by side.

Download the latest `DMC.dmg` from [Releases](https://github.com/jpvalery/dmc/releases/latest).
Needs macOS 15 or later on Apple Silicon. DMC is not notarized, so the first launch of each
version needs **System Settings → Privacy & Security → Open Anyway**.

## Repository

| Folder | What it is |
|---|---|
| [`app/`](app/) | The macOS app: a Swift package, its resources, tools and verification checks. [Read more](app/README.md). |
| [`site/`](site/) | The website: Astro and Tailwind, deployed on Vercel. [Read more](site/README.md). |
| [`macropad/`](macropad/) | QMK firmware and the layout for the Winry315 pad. [Read more](macropad/README.md). |
| `.github/workflows/` | `release.yml` builds and publishes `DMC.dmg` when a `v*` tag is pushed. |

## Common commands

```sh
make run        # build the app and launch it (forwards to app/)
make dmg        # build app/build/DMC.dmg and its checksum
make site-dev   # run the website locally
make site       # build the website into site/dist
```

## Releasing

1. Set `CFBundleShortVersionString` in `app/Resources/Info.plist` to the new version and commit.
2. Tag and push: `git tag v0.2.0 && git push origin v0.2.0`.
3. The release workflow builds `DMC.dmg`, publishes the release with generated notes, and, if the
   `VERCEL_DEPLOY_HOOK` secret is set, redeploys the site so it shows the new version.

## Licence

MIT for the code. Tabletop Audio's catalogue metadata (`app/Resources/tta_data.json`) and any
audio you download stay under their own terms. Not affiliated with Wizards of the Coast.
