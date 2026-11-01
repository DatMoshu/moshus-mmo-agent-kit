#!/usr/bin/env python3
"""Vendor the shard core from Moshu's MMO Agent Kit into a game repo, and check it stays untouched.

The core (server/src/core, the Godot client's core/net/render/ui/scenes, tools/shard, docs/SHARD_CORE.md and
docs/VOXEL_TABLE.md) lives in the kit (templates/server/rust-shard, templates/client/godot-shard, tools/shard,
docs/). A game repo copies it verbatim and records kit commit + sha256 per file in CORE_VENDOR.json (text hashed with
LF line endings, so CRLF checkouts pass --check).
Change core behaviour in the kit (where Meadowmere tests it), then re-vendor; game code never lives in a
vendored path.

    python tools/shard/vendor_core.py --check            # exit 1 if a vendored file changed or is missing
    python tools/shard/vendor_core.py --from KIT_DIR     # copy the core from a kit checkout, rewrite the manifest
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "CORE_VENDOR.json"
# kit path (relative to the kit root) -> game path (relative to the game root); directories are copied whole
MAP = [
    ("templates/server/rust-shard/src/core", "server/src/core"),
    ("templates/client/godot-shard/core", "client/core"),
    ("templates/client/godot-shard/net", "client/net"),
    ("templates/client/godot-shard/render", "client/render"),
    ("templates/client/godot-shard/ui", "client/ui"),
    ("templates/client/godot-shard/scenes", "client/scenes"),
    ("tools/shard", "tools/shard"),
    ("docs/SHARD_CORE.md", "docs/SHARD_CORE.md"),
    ("docs/VOXEL_TABLE.md", "docs/VOXEL_TABLE.md"),
]
SKIP_PARTS = {"__pycache__", ".godot", "target"}


def _files(base: Path) -> list[Path]:
    if base.is_file():
        return [base]
    return sorted(p for p in base.rglob("*") if p.is_file() and not (set(p.parts) & SKIP_PARTS))


def _sha(p: Path) -> str:
    """sha256 of the file with text line endings normalised (CRLF -> LF), so a Windows checkout with
    core.autocrlf=true hashes the same as the LF files in git. Binary files (a NUL in the first 8 KiB) are hashed
    as they are."""
    data = p.read_bytes()
    if b"\0" not in data[:8192]:
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()


def vendor(kit: Path) -> int:
    kit = kit.resolve()
    try:
        commit = subprocess.run(["git", "-C", str(kit), "rev-parse", "HEAD"], capture_output=True, text=True,
                                check=True).stdout.strip()
        dirty = subprocess.run(["git", "-C", str(kit), "status", "--porcelain", "--", *[k for k, _ in MAP]],
                               capture_output=True, text=True, check=True).stdout.strip() != ""
    except (OSError, subprocess.CalledProcessError):
        commit, dirty = "unknown", True
    files = {}
    for k, g in MAP:
        src, dst = kit / k, ROOT / g
        if not src.exists():
            sys.exit(f"kit is missing {k}; is {kit} a kit checkout with the shard templates?")
        if src.is_dir() and dst.exists():  # whole-directory vendoring: stale files go too
            keep = {p.relative_to(src) for p in _files(src)}
            for p in _files(dst):
                if p.relative_to(dst) not in keep:
                    p.unlink()
        for p in _files(src):
            out = dst / p.relative_to(src) if src.is_dir() else dst
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, out)
            files[out.relative_to(ROOT).as_posix()] = _sha(out)
    MANIFEST.write_text(json.dumps({"kit_commit": commit + ("+dirty" if dirty else ""), "map": MAP,
                                    "files": files}, indent=1) + "\n", encoding="utf-8")
    print(f"vendored {len(files)} core files from kit {commit}{' (dirty)' if dirty else ''}")
    return 0


def check() -> int:
    if not MANIFEST.exists():
        print("CORE_VENDOR.json missing: run --from KIT_DIR")
        return 1
    m = json.loads(MANIFEST.read_text(encoding="utf-8"))
    bad = []
    for rel, sha in m["files"].items():
        p = ROOT / rel
        if not p.exists():
            bad.append(f"missing  {rel}")
        elif _sha(p) != sha:
            bad.append(f"modified {rel}")
    for _, g in m["map"]:
        for p in _files(ROOT / g) if (ROOT / g).exists() else []:
            rel = p.relative_to(ROOT).as_posix()
            if rel not in m["files"]:
                bad.append(f"extra    {rel} (game code does not belong in a vendored path)")
    for b in bad:
        print("  " + b)
    print(f"core vendor check: {len(m['files'])} files from kit {m['kit_commit']}: {'FAIL' if bad else 'PASS'}")
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", action="store_true")
    g.add_argument("--from", dest="kit", type=Path)
    a = ap.parse_args()
    return check() if a.check else vendor(a.kit)


if __name__ == "__main__":
    sys.exit(main())
