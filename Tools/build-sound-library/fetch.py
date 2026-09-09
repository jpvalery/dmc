#!/usr/bin/env python3
"""Fetch the Turbo Bard tracks that no pack uses, sorted into a browsable library.

The 13 packs only draw on 55 of their 316 tracks. The rest are the useful remainder: loops to
layer into your own scenes and one-shots to bind as effects. Sorted by what they are, because a
flat folder of 300 files is not a library.

    Ambience/  looping beds that aren't music
    Music/     looping tracks tagged music
    Effects/   one-shots, with their sporadic timings recorded in index.json

Re-runnable: anything already on disk is skipped.
"""
import json, base64, os, sys, time, urllib.request, collections

BUCKET = "https://storage.googleapis.com/turbo-bard.appspot.com"
ROOT = os.path.expanduser("~/DMConsole/audio/Turbo Bard")

def gh(path):
    url = f"https://api.github.com/repos/bencodrington/turbo-bard/contents/{path}"
    return base64.b64decode(json.load(urllib.request.urlopen(url))["content"]).decode()

def main():
    tracks = json.loads(gh("database/tracks.json"))
    tracks = tracks if isinstance(tracks, list) else list(tracks.values())

    # Whatever the packs already put at the folder root is left alone.
    have_root = {f for f in os.listdir(ROOT) if f.endswith(".mp3")} if os.path.isdir(ROOT) else set()

    plan, index = [], []
    for track in tracks:
        files = ([track["fileName"]] if track.get("fileName") else []) + track.get("samples", [])
        if not files or any(f"{f}.mp3" in have_root for f in files):
            continue
        tags = [t.lower() for t in track.get("tags", [])]
        if track.get("type") == "ONESHOT":
            bucket = "Effects"
        elif "music" in tags:
            bucket = "Music"
        else:
            bucket = "Ambience"
        for f in files:
            plan.append((bucket, f))
        index.append({
            "name": track.get("name"),
            "category": bucket,
            "type": track.get("type"),
            "files": [f"Turbo Bard/{bucket}/{f}.mp3" for f in files],
            "tags": track.get("tags", []),
            "minGap": track.get("minSecondsBetween"),
            "maxGap": track.get("maxSecondsBetween"),
            "source": track.get("source"),
        })

    print(f"  {len(index)} tracks, {len(plan)} files", flush=True)
    print("  " + ", ".join(f"{k} {v}" for k, v in
                           collections.Counter(b for b, _ in plan).items()), flush=True)

    got, skipped, failed = 0, 0, []
    for i, (bucket, name) in enumerate(plan):
        folder = os.path.join(ROOT, bucket)
        os.makedirs(folder, exist_ok=True)
        dest = os.path.join(folder, name + ".mp3")
        if os.path.exists(dest) and os.path.getsize(dest) > 0:
            skipped += 1
            continue
        try:
            with urllib.request.urlopen(f"{BUCKET}/{name}.mp3", timeout=60) as r, \
                 open(dest, "wb") as out:
                out.write(r.read())
            got += 1
        except Exception as e:
            failed.append((name, str(e)[:40]))
        time.sleep(0.08)
        if (i + 1) % 50 == 0:
            print(f"  {i+1}/{len(plan)}", flush=True)

    json.dump(index, open(os.path.join(ROOT, "index.json"), "w"), indent=2, sort_keys=True)

    credits = collections.defaultdict(list)
    for entry in index:
        src = entry.get("source") or {}
        credits[(src.get("author") or "Unknown", tuple(src.get("urls") or []))].append(entry["name"])
    lines = ["# Attribution", "",
             "Re-hosted by Turbo Bard (https://turbobard.com); licences come from the original",
             "libraries below, not from Turbo Bard. For personal, non-commercial use.", ""]
    for (author, urls), names in sorted(credits.items()):
        lines.append(f"- **{author}** — {len(names)} track(s)")
        for u in urls:
            lines.append(f"  - {u}")
    open(os.path.join(ROOT, "ATTRIBUTION-library.md"), "w").write("\n".join(lines) + "\n")

    print(f"\n  downloaded {got}, already present {skipped}, failed {len(failed)}", flush=True)
    for f in failed[:5]:
        print("   failed:", f, flush=True)

if __name__ == "__main__":
    main()
