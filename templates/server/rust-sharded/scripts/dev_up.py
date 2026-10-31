#!/usr/bin/env python3
"""Publish and wire a local sharded world: one global database + N region databases.

    python scripts/dev_up.py                         # 2 regions on http://127.0.0.1:3000
    python scripts/dev_up.py --regions 4 --server http://127.0.0.1:3000 --prefix mygame
    python scripts/dev_up.py --wipe                  # delete data and start over (dev only)

What it does (the same steps as the README runbook):
  1. builds the workspace (cargo, wasm32)
  2. publishes `global` once and `region` once per region
  3. registers each region in global (register_region = IDC allow-list)
  4. configures each region (id, x bounds, global identity) and peers neighbours (add_peer)

The world is split into vertical strips of equal width between --x-min and --x-max.
The CLI identity that publishes becomes the admin of every database.
Set SPACETIME=/path/to/spacetime if the CLI is not on PATH.
"""
import argparse, json, os, re, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
CLI = os.environ.get("SPACETIME", "spacetime")
WASM = HERE / "target" / "wasm32-unknown-unknown" / "release"


def run(*args, check=True):
    p = subprocess.run([CLI, *args], cwd=HERE, capture_output=True, text=True)
    out = (p.stdout or "") + (p.stderr or "")
    if check and p.returncode != 0:
        sys.exit(f"FAILED: {CLI} {' '.join(args)}\n{out}")
    return out


def publish(server, name, wasm, wipe):
    args = ["publish", "-s", server, "--bin-path", str(WASM / wasm), "--no-config", "-y", name]
    if wipe:
        args.insert(1, "--delete-data")
    out = run(*args)
    m = re.search(r"identity: ([0-9a-f]{64})", out)
    if not m:
        sys.exit(f"could not read the identity of {name}:\n{out}")
    print(f"published {name}: 0x{m.group(1)}")
    return "0x" + m.group(1)


def call(server, db, reducer, *args):
    run("call", "--no-config", "-s", server, db, reducer, "--", *[json.dumps(a) for a in args])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--server", default="http://127.0.0.1:3000")
    ap.add_argument("--prefix", default="mmo")
    ap.add_argument("--regions", type=int, default=2)
    ap.add_argument("--x-min", type=float, default=-500.0)
    ap.add_argument("--x-max", type=float, default=500.0)
    ap.add_argument("--wipe", action="store_true", help="delete existing data (dev only)")
    ap.add_argument("--skip-build", action="store_true")
    a = ap.parse_args()
    if a.regions < 1 or a.regions > 64:
        sys.exit("--regions must be 1..64")
    if not a.skip_build:
        subprocess.run(["cargo", "build", "--target", "wasm32-unknown-unknown", "--release"], cwd=HERE, check=True)

    g = publish(a.server, f"{a.prefix}-global", "mmo_global.wasm", a.wipe)
    width = (a.x_max - a.x_min) / a.regions
    regions = []
    for i in range(1, a.regions + 1):
        name = f"{a.prefix}-region-{i}"
        lo = a.x_min + (i - 1) * width
        hi = a.x_max if i == a.regions else lo + width
        regions.append((i, name, publish(a.server, name, "mmo_region.wasm", a.wipe), lo, hi))

    for rid, name, ident, lo, hi in regions:
        call(a.server, f"{a.prefix}-global", "register_region", rid, ident, name, lo, hi)
        call(a.server, name, "configure_region", rid, lo, hi, g)
    for rid, name, ident, lo, hi in regions:
        for prid, _pname, pident, plo, phi in regions:
            if abs(prid - rid) == 1:
                call(a.server, name, "add_peer", prid, pident, plo, phi)
    print(f"ok: {a.prefix}-global + {a.regions} regions wired on {a.server}")
    for rid, name, _ident, lo, hi in regions:
        print(f"  region {rid}: {name}  x in [{lo:g}, {hi:g})")


if __name__ == "__main__":
    main()
