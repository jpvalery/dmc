#!/usr/bin/env python3
"""Write the demo vault used for the site's screenshots: one campaign, "The Salt Road".

    python3 make-demo-vault.py <vault> [<audio library>]

Writes campaigns.json and the campaign's scenes, effects, tabs, combat state and notes, then
copies the Turbo Bard files those scenes use from the audio library (default ~/DMConsole/audio).
Nothing from a real campaign is read. See ../README.md for how to shoot with it.
"""
import json, os, shutil, sys, uuid, time
V = sys.argv[1]
LIBRARY = os.path.expanduser(sys.argv[2] if len(sys.argv) > 2 else "~/DMConsole/audio")
U = lambda: str(uuid.uuid4()).upper()
ref = time.time() - 978307200  # seconds since 2001-01-01 (Foundation reference date)
cid = U()
camp = os.path.join(V, "campaigns", cid)
os.makedirs(os.path.join(camp, "notes"), exist_ok=True)
def dump(path, obj):
    with open(path, "w") as f: json.dump(obj, f, indent=2, sort_keys=True)
dump(os.path.join(V, "campaigns.json"), {"activeID": cid, "campaigns": [
    {"id": cid, "name": "The Salt Road", "created": ref - 86400*60, "lastOpened": ref}]})

TB = "Turbo Bard/"
def L(file, gain=0.8, loops=True, sporadic=False, minGap=8, maxGap=20, variants=(), randomStart=True):
    return {"id": U(), "file": TB+file, "gain": gain, "loops": loops and not sporadic, "randomStart": randomStart,
            "pan": 0, "sporadic": sporadic, "minGap": minGap, "maxGap": maxGap, "variants": [TB+v for v in variants]}
def S(name, symbol, layers):
    return {"id": U(), "name": name, "symbol": symbol, "layers": layers, "fadeIn": 1.5, "fadeOut": 2.0}
scenes = [
  S("Tavern", "mug.fill", [L("restaurant-ambience.mp3", .8), L("hearth.mp3", .5), L("jig-of-slurs.mp3", .3),
      L("Effects/glass-1.mp3", .45, sporadic=True, minGap=5, maxGap=20, variants=["Effects/glass-2.mp3"]),
      L("Ambience/creaky-floorboards.mp3", .35)]),
  S("Salt Road", "figure.walk", [L("horse-on-stone.mp3", .6), L("Ambience/beach-ambience.mp3", .45),
      L("saddlebags.mp3", .4, sporadic=True, minGap=12, maxGap=40)]),
  S("Road ambush", "exclamationmark.shield.fill", [L("stand-and-fight.mp3", .55, randomStart=False),
      L("sword-clash-1.mp3", .5, sporadic=True, minGap=3, maxGap=9, variants=["sword-clash-2.mp3", "sword-clash-3.mp3"])]),
  S("Campfire", "flame.fill", [L("campfire.mp3", .75), L("crickets.mp3", .4)]),
  S("Sea caves", "water.waves", [L("cave-ambience.mp3", .7), L("dripping-walls.mp3", .5),
      L("huge-waves-1.mp3", .45, sporadic=True, minGap=10, maxGap=30)]),
  S("Saltmere", "building.2.fill", [L("city-streets.mp3", .7)]),
  S("Haunted chapel", "moon.stars.fill", [L("Ambience/churchyard-at-night.mp3", .7), L("ominous-ambience.mp3", .45),
      L("ghosts-pass-by.mp3", .35, sporadic=True, minGap=15, maxGap=45)]),
  S("Dragon's lair", "lizard.fill", [L("Ambience/dragon-breathing.mp3", .7), L("Ambience/bubbling-lava.mp3", .5),
      L("dragon-snarl.mp3", .5, sporadic=True, minGap=20, maxGap=60)]),
]
dump(os.path.join(camp, "scenes.json"), scenes)
def E(name, symbol, file, gain=.9, variants=(), duck=0):
    return {"id": U(), "name": name, "symbol": symbol, "file": TB+file, "gain": gain, "variants": [TB+v for v in variants], "duck": duck}
effects = [
  E("Door creak", "door.left.hand.open", "Effects/door-creak-1.mp3", variants=["Effects/door-creak-2.mp3", "Effects/door-creak-3.mp3"]),
  E("Battle horn", "megaphone.fill", "Effects/battle-horn.mp3", duck=.4),
  E("Dragon roar", "speaker.wave.3.fill", "dragon-roar.mp3", duck=.6),
  E("Dice", "dice.fill", "Effects/five-dice-on-felt.mp3", gain=.8),
  E("Coins", "dollarsign.circle.fill", "counting-coins-1.mp3", variants=["counting-coins-2.mp3", "counting-coins-3.mp3"]),
  E("Swords", "shield.lefthalf.filled", "sword-clash-1.mp3", variants=["sword-clash-2.mp3", "sword-clash-3.mp3"]),
  E("Scream", "exclamationmark.bubble.fill", "Effects/female-scream.mp3", duck=.3),
]
dump(os.path.join(camp, "effects.json"), effects)
dump(os.path.join(camp, "tabs.json"), [
  "https://www.dndbeyond.com/monsters/16799-bandit-captain",
  "https://www.dndbeyond.com/sources/dnd/br-2024/rules-glossary",
  "https://www.dndbeyond.com/monsters/16953-mastiff"])

ambush = next(s for s in scenes if s["name"] == "Road ambush")
def C(name, init, bonus, ac, hp, maxhp, pc=False, conds=()):
    return {"id": U(), "name": name, "initiative": init, "initiativeBonus": bonus, "armorClass": ac, "hp": hp, "maxHP": maxhp,
            "isPlayer": pc, "conditions": [{"id": U(), "name": n, **({"rounds": r} if r else {})} for n, r in conds],
            "deathSuccesses": 0, "deathFailures": 0, "isLair": False}
brakka = C("Brakka", 19, 1, 16, 31, 44, pc=True)
cbs = [brakka,
  C("Bandit captain", 17, 3, 15, 41, 65),
  C("Wren", 15, 3, 13, 22, 22, pc=True, conds=[("Concentrating", None)]),
  C("Mastiff", 14, 2, 12, 5, 5, conds=[("Prone", None)]),
  C("Bandit 1", 12, 1, 12, 4, 11),
  C("Bandit 2", 12, 1, 12, 0, 11),
  C("Ilsa", 8, 2, 14, 9, 27, pc=True, conds=[("Poisoned", 2)]),
]
enc1 = {"id": U(), "name": "Road ambush", "sceneID": ambush["id"], "done": False, "monsters": [
  {"id": U(), "name": "Bandit captain", "count": 1, "armorClass": 15, "hp": 65, "initiativeBonus": 3},
  {"id": U(), "name": "Bandit", "count": 2, "armorClass": 12, "hp": 11, "initiativeBonus": 1},
  {"id": U(), "name": "Mastiff", "count": 1, "armorClass": 12, "hp": 5, "initiativeBonus": 2}]}
enc2 = {"id": U(), "name": "The drowned lighthouse", "sceneID": next(s for s in scenes if s["name"] == "Sea caves")["id"], "done": False,
  "monsters": [{"id": U(), "name": "Sahuagin", "count": 3, "armorClass": 12, "hp": 22, "initiativeBonus": 0}]}
dump(os.path.join(camp, "combat.json"), {"combatants": cbs, "round": 3, "currentID": brakka["id"],
  "encounters": [enc1, enc2], "activeEncounterID": enc1["id"]})

notes = os.path.join(camp, "notes")
older = {
 "2026-09-18 Session 10.md": "# Session 10\n\nThe party leaves the abbey with the sealed letter.\n\n## Log\n- 19:40 Scene: Haunted chapel\n",
 "2026-09-25 Session 11.md": "# Session 11\n\nThree days on the coast road. Wren hears singing under the cliffs.\n\n[[scene:Sea caves]]\n\n## Log\n- 20:05 Scene: Salt Road\n- 21:30 Scene: Sea caves\n",
}
for n, t in older.items():
    p = os.path.join(notes, n); open(p, "w").write(t)
    os.utime(p, (time.time() - 86400*10, time.time() - 86400*10))
s12 = """# Session 12

## Arrival
The caravan reaches **Saltmere** at dusk. Rain off the sea, gulls on every roof.
Odo, the innkeeper, saw the ferry leave without its lantern.

[[scene:Tavern]]

- [ ] Ask about the lighthouse keeper
- [x] Hand out the harbour map
- [ ] Brakka owes Odo 4 gp

## The road north
Bandits wait where the road narrows between the dunes. Captain Vessa wants the map, not a fight.

[[scene:Road ambush]] then [[effect:Battle horn]]

If they parley: [[stop]], then [[scene:Campfire]]

## Log
- 20:14 Scene: Tavern
- 21:02 Scene: Road ambush
- 21:03 Combat started
- 21:05 Round 2
- 21:07 Round 3
- 21:09 Bandit 2 drops to 0 HP
"""
open(os.path.join(notes, "2026-10-02 Session 12.md"), "w").write(s12)

# Copy only the audio the demo uses, with Turbo Bard's attribution files beside it.
wanted = {l["file"] for s in scenes for l in s["layers"]} | {v for s in scenes for l in s["layers"] for v in l["variants"]}
wanted |= {e["file"] for e in effects} | {v for e in effects for v in e["variants"]}
wanted |= {TB + "ATTRIBUTION.md", TB + "ATTRIBUTION-library.md"}
missing = []
for rel in sorted(wanted):
    src, dst = os.path.join(LIBRARY, rel), os.path.join(V, "audio", rel)
    if not os.path.exists(src):
        missing.append(rel); continue
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
if missing:
    print("missing from the library (the app will flag these layers):", *missing, sep="\n  ", file=sys.stderr)
print(cid)
