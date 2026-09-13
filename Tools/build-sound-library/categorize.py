#!/usr/bin/env python3
"""Group the vault by what a sound is for, not where it came from.

Folders record provenance — Turbo Bard, Tabletop Audio — which matters for attribution and
nothing else. When you are building a scene you want "Dungeon & Cave", not "whose server did
this arrive from". This writes categories.json mapping each vault-relative path to a category,
leaving the files themselves alone so existing scenes keep working.

Rules are ordered: the first match wins, so "music" only claims a track that nothing more
specific already did.
"""
import json, os, collections

AUDIO = os.path.expanduser("~/DMConsole/audio")
HERE = os.path.dirname(os.path.abspath(__file__))

RULES = [
    ("Combat",           ["battle", "combat", "fight", "war", "army", "siege", "sword",
                          "melee", "weapon", "charge", "attack", "arrow", "shield", "clash",
                          "explosion", "destruction", "crash", "break", "shatter", "shard"]),
    ("Horror & Undead",  ["spook", "horror", "eerie", "evil", "haunt", "ghost", "undead",
                          "crypt", "graveyard", "creepy", "necroman", "zombie", "wraith",
                          "vampire", "ominous", "sinister", "scream", "demon", "cult"]),
    ("Dungeon & Cave",   ["dungeon", "cave", "cavern", "underground", "drip", "tunnel",
                          "mine", "catacomb", "echo", "lava", "magma", "torch", "dark"]),
    ("Tavern & Town",    ["tavern", "inn", "pub", "village", "town", "city", "market",
                          "crowd", "voice", "street", "festive", "celebrat", "drink",
                          "child", "baby", "infant", "people", "chatter", "applause", "bard"]),
    ("Wilderness",       ["forest", "wood", "jungle", "swamp", "nature", "wildlife",
                          "mountain", "travel", "camp", "field", "meadow", "desert",
                          "farm", "graz", "badland", "outdoor", "leaves", "night"]),
    ("Water & Sea",      ["ocean", "sea", "ship", "boat", "sail", "river", "stream",
                          "wave", "underwater", "harbour", "harbor", "water", "splash"]),
    ("Weather",          ["rain", "storm", "thunder", "lightning", "wind", "snow", "blizzard"]),
    ("Magic & Arcane",   ["magic", "spell", "arcane", "ritual", "temple", "portal", "summon",
                          "enchant", "conjur", "transmut", "divine", "acid", "potion"]),
    ("Creatures",        ["dragon", "beast", "monster", "animal", "wolf", "horse", "insect",
                          "goblin", "orc", "troll", "giant", "roar", "growl", "bird", "cow",
                          "sheep", "dog", "cat", "chicken", "bee", "flamingo", "livestock",
                          "snort", "whinny", "hoof"]),
    ("Craft & Industry", ["workshop", "hammer", "chisel", "anvil", "forge", "smith", "machine",
                          "engine", "chain", "hoist", "saw", "gear", "clockwork", "steam"]),
    ("Tools & Meta",     ["meta", "dice", "funny", "comedic", "shenanigan", "coin", "money",
                          "page", "book", "parchment", "quill", "ink", "writ", "door", "chest",
                          "lock", "footstep", "clock", "tick", "glass", "intro", "recap"]),
    ("Music",            ["music", "orchestral", "piano", "string", "drum", "theme", "melody"]),
]
FALLBACK = "Unsorted"

def category_for(name, tags, relative_path=""):
    # Substring rather than exact match, so plurals and compounds land: "pages" hits "page",
    # "whinnying" hits "whinny".
    hay = " ".join(t.lower() for t in tags)
    hay += " " + name.lower().replace("-", " ").replace("_", " ")
    for label, keys in RULES:
        if any(k in hay for k in keys):
            return label
    # Last resort, the folder says something: a file in Music/ is music.
    head = relative_path.split(os.sep)[0].lower()
    if "music" in head:
        return "Music"
    return FALLBACK

def main():
    # Tags for everything we know about: the library index, plus the pack tracks.
    tags_by_stem = {}
    index_path = os.path.join(AUDIO, "Turbo Bard", "index.json")
    if os.path.exists(index_path):
        for entry in json.load(open(index_path)):
            for f in entry.get("files", []):
                tags_by_stem[os.path.splitext(os.path.basename(f))[0]] = entry.get("tags", [])
    resolved = os.path.join(HERE, "..", "build-scene-templates", "resolved.json")
    if os.path.exists(resolved):
        for track in json.load(open(resolved)).values():
            stems = ([track["fileName"]] if track.get("fileName") else []) + track.get("samples", [])
            for stem in stems:
                tags_by_stem.setdefault(stem, track.get("tags", []))

    categories = {}
    for root, _, files in os.walk(AUDIO):
        for f in files:
            if not f.lower().endswith((".mp3", ".m4a", ".wav", ".flac", ".aiff", ".aif")):
                continue
            rel = os.path.relpath(os.path.join(root, f), AUDIO)
            stem = os.path.splitext(f)[0]
            categories[rel] = category_for(stem, tags_by_stem.get(stem, []), rel)

    json.dump(categories, open(os.path.join(AUDIO, "categories.json"), "w"),
              indent=2, sort_keys=True)
    counts = collections.Counter(categories.values())
    print(f"  categorised {len(categories)} files")
    for label, _ in RULES + [(FALLBACK, None)]:
        if counts.get(label):
            print(f"    {counts[label]:4}  {label}")

if __name__ == "__main__":
    main()
