#!/usr/bin/env python3
"""Turn the library's one-shot tracks into DMC effect templates.

Reads the index written by fetch.py and emits Resources/effect-templates.json. Like scene
templates these ship in the bundle, so deleting an effect never loses the recipe, and each
carries download URLs so a template works on a vault that lacks the audio.
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "effect-templates.json")
INDEX = os.path.expanduser("~/DMConsole/audio/Turbo Bard/index.json")
BUCKET = "https://storage.googleapis.com/turbo-bard.appspot.com"

# Tags mapped to icons, most specific first — a bell for everything would be useless.
ICONS = [
    (("coin", "money", "gold", "treasure", "currency"), "dice"),
    (("sword", "combat", "battle", "blade", "melee", "fight"), "shield"),
    (("scream", "death", "killed", "dying", "roar", "snarl"), "figure.fencing"),
    (("spell", "magic", "arcane", "cast", "conjuration"), "wand.and.stars"),
    (("thunder", "storm", "lightning"), "cloud.bolt.rain"),
    (("rain", "water", "drip", "splash"), "drop"),
    (("door", "gate", "creak", "hinge"), "door.left.hand.open"),
    (("fire", "flame", "burn", "torch"), "flame"),
    (("bird", "owl", "crow", "chirp", "wing"), "bird"),
    (("wolf", "beast", "growl", "animal", "horse"), "pawprint"),
    (("bell", "chime", "gong"), "bell"),
    (("crowd", "voices", "cheer", "tavern", "laugh"), "person.3"),
    (("wind", "gust", "breeze"), "wind"),
    (("step", "walk", "footstep"), "figure.walk"),
    (("glass", "bottle", "pour", "drink"), "cup.and.saucer"),
    (("hammer", "anvil", "forge", "metal"), "hammer"),
    (("book", "page", "scroll", "paper"), "book.closed"),
]

def icon_for(name, tags):
    hay = (name + " " + " ".join(tags)).lower()
    for keys, symbol in ICONS:
        if any(k in hay for k in keys):
            return symbol
    return "bolt.fill"

def main():
    index = json.load(open(INDEX))
    templates = []
    for entry in index:
        if entry.get("category") != "Effects":
            continue
        files = entry.get("files") or []
        if not files:
            continue
        stems = [os.path.splitext(os.path.basename(f))[0] for f in files]
        src = entry.get("source") or {}
        templates.append({
            "name": entry.get("name") or stems[0],
            "symbol": icon_for(entry.get("name", ""), entry.get("tags", [])),
            "tags": entry.get("tags", []),
            "gain": 0.85,
            "file": files[0],
            "download": f"{BUCKET}/{stems[0]}.mp3",
            "variants": files[1:],
            "variantDownloads": [f"{BUCKET}/{s}.mp3" for s in stems[1:]],
            "credit": src.get("author") or "",
        })
    templates.sort(key=lambda t: t["name"].lower())
    doc = {
        "note": ("One-shots re-hosted by Turbo Bard; licences come from the original libraries "
                 "(Sonniss GDC, Freesound, FreePD and others). For personal, non-commercial use."),
        "templates": templates,
    }
    json.dump(doc, open(OUT, "w"), indent=2, sort_keys=True)
    multi = sum(1 for t in templates if t["variants"])
    print(f"  {len(templates)} effect templates ({multi} with multiple takes)")

if __name__ == "__main__":
    main()
