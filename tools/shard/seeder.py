#!/usr/bin/env python3
"""Generic MMO-core seeder: loads a neutral world document into a running core module.

Game-agnostic. An adapter (a game's own, or tools/shard/fixture_game.py) writes a
`mmo-core-world/1` JSON document (schema: docs/SHARD_CORE.md, "World document"); this script
turns it into the operator-gated `seed_*` reducer calls, in the order the module requires.

    python tools/shard/seeder.py WORLD.json [--url URL] [--db DB] [--jobs N]

Needs the spacetime CLI ($SPACETIME or on PATH; extra flags in $SPACETIME_ARGS) logged in as the
database owner (seed reducers are admin-only).
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

FORMAT = "mmo-core-world/1"
IS_WIN = os.name == "nt"
TRANSIENT = re.compile(r"connection (refused|reset|aborted|closed)|timed? ?out|temporarily unavailable|50[234]|429", re.I)
CHUNK = 32


def say(msg: str) -> None:
    print(f"[seed] {msg}", flush=True)


def spacetime_cmd() -> list[str]:
    exe = os.environ.get("SPACETIME") or shutil.which("spacetime")
    if not exe:
        raise SystemExit("spacetime CLI not found; set SPACETIME=/path/to/spacetime")
    return [exe, *shlex.split(os.environ.get("SPACETIME_ARGS", ""), posix=not IS_WIN)]


def call(url: str, db: str, reducer: str, *args) -> None:
    cmd = [*spacetime_cmd(), "call", "--server", url, db, reducer, *[json.dumps(a) for a in args]]
    for attempt in range(4):
        r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if r.returncode == 0:
            return
        err = (r.stderr or "") + (r.stdout or "")
        if attempt < 3 and TRANSIENT.search(err):
            time.sleep(2 * 2 ** attempt)
            continue
        raise SystemExit(f"{reducer} failed: {err.strip()[-800:]}")


def validate(doc: dict) -> None:
    if doc.get("format") != FORMAT:
        raise SystemExit(f"not a {FORMAT} document (format={doc.get('format')!r})")
    if len(doc["walkable"]) != 256:
        raise SystemExit("walkable must list 256 tile flags")
    ids = set()
    for m in doc["maps"]:
        w, h = m["width"], m["height"]
        if w % CHUNK or h % CHUNK or len(m["tiles"]) != w * h:
            raise SystemExit(f"map {m['key']}: size must be a multiple of 32 and tiles must be w*h")
        if m["id"] in ids:
            raise SystemExit(f"duplicate map id {m['id']}")
        ids.add(m["id"])
    for p in doc.get("portals", []):
        if p["from_map"] not in ids or p["to_map"] not in ids:
            raise SystemExit(f"portal {p['id']} references an unknown map")


def seed(doc: dict, url: str, db: str, jobs: int = 8) -> dict:
    validate(doc)
    kind = doc["source"]["kind"]
    tag = doc["source"].get("tag") or hashlib.sha256(json.dumps(doc["source"], sort_keys=True).encode()).hexdigest()[:16]
    t0 = time.time()
    say(f"seeding {doc.get('game', '?')} ({kind}/{tag}) into {db} at {url}")
    call(url, db, "seed_begin", kind, tag)
    call(url, db, "seed_tile_rules", [1 if v else 0 for v in doc["walkable"]])
    work = []
    for m in doc["maps"]:
        w, h = m["width"], m["height"]
        call(url, db, "seed_map", m["id"], m["key"], w, h, bool(m.get("exit_at_edge")))
        for cy in range(h // CHUNK):
            for cx in range(w // CHUNK):
                chunk = [m["tiles"][(cy * CHUNK + ty) * w + cx * CHUNK + tx] for ty in range(CHUNK) for tx in range(CHUNK)]
                work.append(("seed_chunk", m["id"], cx, cy, chunk))
    for e in doc.get("map_exits", []):
        work.append(("seed_map_exit", e["map_id"], e["to_map"], e["x"], e["y"]))
    for p in doc.get("portals", []):
        work.append(("seed_portal", p["id"], p["from_map"], p["x"], p["y"], p["to_map"], p["to_x"], p["to_y"]))
    by_map: dict[int, list[dict]] = {}
    for n in doc.get("npcs", []):
        by_map.setdefault(n["map_id"], []).append(n)
    for mid, ns in sorted(by_map.items()):
        work.append(("seed_npcs", mid, [n["slot"] for n in ns], [n["tile"] for n in ns], [n["x"] for n in ns],
                     [n["y"] for n in ns], [1 if n.get("wander") else 0 for n in ns], [n.get("talk", 0) for n in ns]))
    for k in doc.get("monster_kinds", []):
        work.append(("seed_monster_kind", k["kind"], k["name"], k["tile"], k["hp"], k["dmg_min"], k["dmg_max"],
                     k["step_ticks"], k["attack_ticks"], k["aggro"], k["xp"], k["gold_min"], k["gold_max"]))
    for r in doc.get("spawn_rules", []):
        work.append(("seed_spawn_rule", r["id"], r["map_id"], r["max_alive"], r["kinds"], r["min_dist"], r["max_dist"]))
    for z in doc.get("safe_zones", []):
        work.append(("seed_safe_zone", z["id"], z["map_id"], z["x"], z["y"], z["r"]))
    for r in doc.get("respawns", []):
        work.append(("seed_respawn", r["id"], r["map_id"], r["x"], r["y"]))
    for k in doc.get("item_kinds", []):
        work.append(("seed_item_kind", k["kind"], k["name"], k["tile"], k.get("heal", 0)))
    # Every call above is an independent upsert, so they can run in parallel.
    with cf.ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
        for f in [ex.submit(call, url, db, *w) for w in work]:
            f.result()
    s = doc["spawn"]
    call(url, db, "seed_commit", kind, tag, s["map_id"], s["x"], s["y"])
    stats = {"maps": len(doc["maps"]), "calls": len(work) + 4, "portals": len(doc.get("portals", [])),
             "npcs": len(doc.get("npcs", [])), "monster_kinds": len(doc.get("monster_kinds", [])),
             "seconds": round(time.time() - t0, 1)}
    say(f"seeded {stats}")
    return stats


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("world")
    ap.add_argument("--url", default="http://127.0.0.1:3000")
    ap.add_argument("--db", required=True)
    ap.add_argument("--jobs", type=int, default=8)
    a = ap.parse_args()
    seed(json.loads(Path(a.world).read_text(encoding="utf-8")), a.url, a.db, a.jobs)
    return 0


if __name__ == "__main__":
    sys.exit(main())
