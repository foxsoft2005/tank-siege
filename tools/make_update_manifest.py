"""
Writes update.json, the small file the game downloads to find out whether a
newer version exists. Run it every time you publish an update.

Usage:
    python tools/make_update_manifest.py PCK_FILE VERSION PCK_URL [PAGE_URL] [NOTES]

Example:
    python tools/make_update_manifest.py build/tank-siege.pck 1.1.0 \\
        https://github.com/you/tank-siege/releases/download/v1.1.0/tank-siege.pck \\
        https://you.itch.io/tank-siege "New stage and faster drones"

Then upload BOTH files: the .pck to PCK_URL, and update.json to the address
in MANIFEST_URL (scripts/updater.gd). No extra Python packages needed.
"""

import hashlib
import json
import sys


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)
    pck, version, pck_url = sys.argv[1:4]
    manifest = {
        "version": version,
        "notes": sys.argv[5] if len(sys.argv) > 5 else "",
        "pck_url": pck_url,
        "sha256": sha256(pck),
        "page_url": sys.argv[4] if len(sys.argv) > 4 else "",
    }
    with open("update.json", "w") as f:
        json.dump(manifest, f, indent=2)
    print(json.dumps(manifest, indent=2))
    print("\nwrote update.json - remember to bump VERSION in scripts/version.gd too!")


if __name__ == "__main__":
    main()
