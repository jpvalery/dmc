#!/usr/bin/env python3
"""Turn Turbo Bard packs into DMC's bundled scene templates.

Emits Resources/scene-templates.json: each template is a ready-made scene, with a download URL
per file so the app can fetch what the vault is missing, and the credit each source requires.

LOOP tracks become looping layers. ONESHOT tracks become sporadic layers, taking the pack's
per-track timing override when it has one and the track's own defaults otherwise; extra samples
ride along as variants.
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "scene-templates.json")
FOLDER = "Turbo Bard"
BUCKET = "https://storage.googleapis.com/turbo-bard.appspot.com"

SYMBOLS = {
    "graveyard": "moon.stars", "tavern": "cup.and.saucer", "forest": "tree",
    "cave": "mountain.2", "dungeon": "building.columns", "battle": "shield",
    "ocean": "water.waves", "ship": "sailboat", "sea": "sailboat", "town": "building.2",
    "city": "building.2", "camp": "flame", "forge": "hammer", "workshop": "wrench.adjustable",
    "swamp": "leaf", "mountain": "mountain.2", "ruin": "building.columns",
    "jungle": "tree", "dragon": "flame", "underdark": "moon",
}

def symbol_for(pack):
    hay = (pack.get("name", "") + " " + " ".join(pack.get("tags", []))).lower()
    for key, sym in SYMBOLS.items():
        if key in hay:
            return sym
    return "waveform"

def layer(name, gain, sporadic, min_gap, max_gap, variants):
    return {
        "file": f"{FOLDER}/{name}.mp3",
        "download": f"{BUCKET}/{name}.mp3",
        "gain": gain,
        "loops": not sporadic,
        "randomStart": not sporadic,
        "sporadic": sporadic,
        "minGap": min_gap,
        "maxGap": max_gap,
        "variants": [f"{FOLDER}/{v}.mp3" for v in variants],
        "variantDownloads": [f"{BUCKET}/{v}.mp3" for v in variants],
    }

def main():
    packs = json.load(open(os.path.join(HERE, "packs.json")))
    resolved = json.load(open(os.path.join(HERE, "resolved.json")))

    templates = []
    for pack in packs:
        layers, credits = [], set()
        for ref in pack.get("tracks", []):
            track = resolved.get(ref.get("id", ""))
            if not track:
                continue
            gain = float(ref.get("volume", 0.8))
            src = track.get("source") or {}
            if src.get("author"):
                credits.add(src["author"])
            if track.get("type") == "ONESHOT":
                samples = track.get("samples") or []
                if not samples:
                    continue
                cfg = ref.get("oneShotConfig") or {}
                layers.append(layer(
                    samples[0], gain, True,
                    float(cfg.get("minSecondsBetween", track.get("minSecondsBetween", 8))),
                    float(cfg.get("maxSecondsBetween", track.get("maxSecondsBetween", 20))),
                    samples[1:]))
            elif track.get("fileName"):
                layers.append(layer(track["fileName"], gain, False, 8, 20, []))
        if not layers:
            continue
        templates.append({
            "name": pack["name"],
            "symbol": symbol_for(pack),
            "tags": pack.get("tags", []),
            "credit": ", ".join(sorted(credits)),
            "layers": layers,
        })

    doc = {
        "source": "Turbo Bard packs (https://turbobard.com)",
        "note": ("Audio is re-hosted third-party material; licences come from the original "
                 "libraries (Sonniss GDC, Freesound, FreePD and others), not from Turbo Bard. "
                 "For personal, non-commercial use."),
        "templates": templates,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(doc, open(OUT, "w"), indent=2, sort_keys=True)
    files = {l["file"] for t in templates for l in t["layers"]}
    files |= {v for t in templates for l in t["layers"] for v in l["variants"]}
    print(f"  {len(templates)} templates, {len(files)} distinct audio files")

if __name__ == "__main__":
    main()
