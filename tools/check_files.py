#!/usr/bin/env python3
"""Verify (or refresh) the md5 of everything shipped in releases/.

    python3 tools/check_files.py            # verify against releases/md5sums.txt
    python3 tools/check_files.py --update   # rewrite md5sums.txt from what is there

A released bitstream is the one artefact a user cannot rebuild and cannot
check by eye, so it gets a hash next to it. The MRAs are hashed too: they
carry the ROM CRCs, and a truncated or half-edited MRA fails in ways that
look like a broken core.

`md5sum -c md5sums.txt` run from releases/ does the same thing; this script
exists so the check says WHAT each file is when one does not match.
"""
import argparse
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REL = os.path.join(os.path.dirname(HERE), "releases")
SUMS = os.path.join(REL, "md5sums.txt")

WHAT = {
    ".rbf": "the core bitstream -- copy to /media/fat/_Arcade/cores/",
    ".mra": "an arcade definition -- copy to /media/fat/_Arcade/",
}

HEADER = """# md5 of each file shipped in releases/. Regenerate with:
#     python3 tools/check_files.py --update
# Verify with either:
#     python3 tools/check_files.py
#     md5sum -c md5sums.txt      (run from releases/)
"""


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def shipped():
    # releases/ only -- releases/experimental/ holds things that do not work
    # yet and is deliberately not hashed or advertised
    return sorted(f for f in os.listdir(REL)
                  if os.path.splitext(f)[1] in WHAT
                  and os.path.isfile(os.path.join(REL, f)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--update", action="store_true", help="rewrite md5sums.txt")
    a = ap.parse_args()

    files = shipped()
    if not files:
        sys.exit(f"nothing to hash in {REL}")

    if a.update:
        with open(SUMS, "w") as f:
            f.write(HEADER)
            for name in files:
                f.write(f"{md5(os.path.join(REL, name))}  {name}\n")
        print(f"wrote {SUMS} ({len(files)} files)")
        return

    if not os.path.exists(SUMS):
        sys.exit(f"{SUMS} not found -- run with --update to create it")

    want = {}
    for line in open(SUMS):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        h, _, name = line.partition("  ")
        want[name] = h

    bad = 0
    for name in files:
        ext = os.path.splitext(name)[1]
        if name not in want:
            print(f"NOT LISTED  {name} -- {WHAT[ext]}")
            bad += 1
            continue
        got = md5(os.path.join(REL, name))
        if got == want[name]:
            print(f"ok          {name}")
        else:
            print(f"MISMATCH    {name} -- {WHAT[ext]}")
            print(f"            expected {want[name]}, got {got}")
            bad += 1
    for name in want:
        if name not in files:
            print(f"MISSING     {name} -- listed in md5sums.txt but not present")
            bad += 1

    if bad:
        sys.exit(f"{bad} problem(s)")
    print(f"all {len(files)} files match")


if __name__ == "__main__":
    main()
