#!/bin/bash
# Fetch the curated pets (Boba / Capy / Scoop) from the petdex catalog into
# ~/.hermes/pets so the app's pet picker has options. Best-effort: never fails
# (used by both install-menubar.sh and the Homebrew formula's post_install).
/usr/bin/python3 - <<'PY' || true
import urllib.request, os, json
pets = {
    "boba":  ("Boba",  "https://assets.petdex.dev/curated/boba/sprite-v2.webp"),
    "capy":  ("Capy",  "https://assets.petdex.dev/pets/capy-c8b8801eb785/sprite.webp"),
    "scoop": ("Scoop", "https://assets.petdex.dev/curated/scoop/spritesheet.webp"),
}
base = os.path.expanduser("~/.hermes/pets")
for slug, (name, url) in pets.items():
    directory = os.path.join(base, slug)
    sheet = os.path.join(directory, "spritesheet.webp")
    if os.path.exists(sheet) and os.path.getsize(sheet) > 1000:
        continue
    os.makedirs(directory, exist_ok=True)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "hermes-agent-petdex"})
        open(sheet, "wb").write(urllib.request.urlopen(req, timeout=30).read())
        json.dump({"id": slug, "displayName": name, "spritesheetPath": "spritesheet.webp"},
                  open(os.path.join(directory, "pet.json"), "w"), indent=2)
        print(f"  fetched pet: {slug}")
    except Exception as exc:
        print(f"  (skipped pet {slug}: {exc})")
PY
