#!/usr/bin/env python3
"""Synthetic second game adapter ("Meadowmere"): proof that the MMO core is game-agnostic.

Everything here is generated from code (no files are read, nothing from any commercial game), so the
document may be committed, shared and used in CI. It produces the same `mmo-core-world/1` document an
game adapter does (schema: docs/SHARD_CORE.md) with its own tile ids, two maps, a village with
talking NPCs, a portal, monsters, safe zones and respawns.

    python tools/shard/fixture_game.py check               # build + validate offline (no server)
    python tools/shard/fixture_game.py write OUT.json      # write the document
    python tools/shard/fixture_game.py live --db fixture-dev [--url URL] [--publish]
        # (optionally publish the core module to a separate DB,) seed it, then verify the seeded rows with SQL
    python tools/shard/fixture_game.py live --db fixture-dev --godot GODOT --logs EVIDENCE_DIR
        # two concurrent clients, each with isolated user data and a complete output log

`live` needs the spacetime CLI ($SPACETIME, $SPACETIME_ARGS) logged in as the database owner.
"""
from __future__ import annotations

import argparse
import json
import os
import random
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# a game repo has client/ + server/; the kit itself keeps them as the shard templates
CLIENT = ROOT / "client" if (ROOT / "client").exists() else ROOT / "templates" / "client" / "godot-shard"
SERVER = ROOT / "server" if (ROOT / "server").exists() else ROOT / "templates" / "server" / "rust-shard"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import seeder  # noqa: E402

# Tile ids are this game's own. 0 water, 1 grass, 2 trees, 3 stone wall, 4 floor, 5 road, 6 village sign
# (portal), 7 bridge; 64.. creature sprites (67 = the player); 96 gold, 97 herb.
WATER, GRASS, TREES, WALL, FLOOR, ROAD, SIGN, BRIDGE = range(8)
WALKABLE = {GRASS, TREES, FLOOR, ROAD, SIGN, BRIDGE}
SURFACE, VILLAGE = 0, 1
W0, W1 = 64, 32


def surface() -> list[int]:
    rng = random.Random(7)
    t = [GRASS] * (W0 * W0)
    for y in range(W0):
        for x in range(W0):
            if x in (0, W0 - 1) or y in (0, W0 - 1) or (x - 44) ** 2 + (y - 18) ** 2 < 49:
                t[y * W0 + x] = WATER      # border sea + a lake
            elif rng.random() < 0.12:
                t[y * W0 + x] = TREES
    for x in range(8, 40):
        t[32 * W0 + x] = ROAD
    t[32 * W0 + 40] = SIGN                 # the village entrance (portal)
    return t


def village() -> list[int]:
    t = [GRASS] * (W1 * W1)
    for y in range(W1):
        for x in range(W1):
            if 8 <= x <= 20 and 6 <= y <= 14 and (x in (8, 20) or y in (6, 14)):
                t[y * W1 + x] = WALL       # the inn
            elif 9 <= x <= 19 and 7 <= y <= 13:
                t[y * W1 + x] = FLOOR
    t[14 * W1 + 14] = FLOOR                # inn door
    for x in range(0, W1):
        t[16 * W1 + x] = ROAD
    return t


def build() -> dict:
    s, v = surface(), village()
    npcs = [
        {"map_id": VILLAGE, "slot": 0, "tile": 64, "x": 12, "y": 10, "wander": True, "talk": 1},   # innkeeper
        {"map_id": VILLAGE, "slot": 1, "tile": 65, "x": 24, "y": 18, "wander": True, "talk": 2},   # farmer
        {"map_id": VILLAGE, "slot": 2, "tile": 66, "x": 5, "y": 20, "wander": False, "talk": 0},   # a cow
    ]
    return {
        "format": seeder.FORMAT,
        "game": "meadowmere-fixture",
        "source": {"kind": "fixture", "tag": "meadowmere-v1"},
        "walkable": [t in WALKABLE for t in range(256)],
        "maps": [
            {"id": SURFACE, "key": "meadow", "width": W0, "height": W0, "tiles": s, "exit_at_edge": False},
            {"id": VILLAGE, "key": "hollow", "width": W1, "height": W1, "tiles": v, "exit_at_edge": True},
        ],
        "map_exits": [{"map_id": VILLAGE, "to_map": SURFACE, "x": 40, "y": 32}],
        "portals": [{"id": 1, "name": "hollow", "from_map": SURFACE, "x": 40, "y": 32, "to_map": VILLAGE, "to_x": 1, "to_y": 16}],
        "npcs": npcs,
        "monster_kinds": [
            {"kind": 1, "name": "field mouse", "tile": 80, "hp": 4, "dmg_min": 1, "dmg_max": 2, "step_ticks": 6,
             "attack_ticks": 20, "aggro": 4, "xp": 6, "gold_min": 1, "gold_max": 3,
             "ai": {"flee_hp_pct": 25, "pack": 5}},
            {"kind": 2, "name": "bog wisp", "tile": 82, "hp": 12, "dmg_min": 2, "dmg_max": 4, "step_ticks": 8,
             "attack_ticks": 20, "aggro": 6, "xp": 15, "gold_min": 2, "gold_max": 6,
             "ai": {"range": 4, "keep_dist": 2}},
        ],
        "spawn_rules": [{"id": 1, "map_id": SURFACE, "max_alive": 10, "kinds": [1, 1, 2], "min_dist": 6, "max_dist": 12}],
        "safe_zones": [{"id": 0, "map_id": SURFACE, "x": 20, "y": 32, "r": 6},
                       {"id": 1, "map_id": VILLAGE, "x": 15, "y": 15, "r": 64}],
        "respawns": [{"id": 0, "map_id": SURFACE, "x": 20, "y": 32}, {"id": 1, "map_id": VILLAGE, "x": 2, "y": 16}],
        "item_kinds": [{"kind": 0, "name": "gold", "tile": 96, "heal": 0},
                       {"kind": 1, "name": "herb", "tile": 97, "heal": 10}],
        "spawn": {"map_id": SURFACE, "x": 20, "y": 32},
        # client-only (the server ignores it): flat colours and dialogue for core/doc_source.gd
        "client": {
            "colors": {str(WATER): "#2b5fa8", str(GRASS): "#5d9b3c", str(TREES): "#2f6b2a", str(WALL): "#7b6f63",
                       str(FLOOR): "#b08a5a", str(ROAD): "#c9b27c", str(SIGN): "#e0c040", str(BRIDGE): "#8a5a2b",
                       "64": "#f0d0a0", "65": "#c08040", "66": "#f4f4f4", "67": "#4060ff", "80": "#9a9a9a", "82": "#a0f0ff",
                       "96": "#ffd700", "97": "#40e070"},
            "player_tile": 67,
            # 3D view (docs/VOXEL_TABLE.md): heights per tile category; flat colours carry no pixel rules
            "voxel": {
                "categories": {k: dict(v, pixels={"*": {"colour": v["ground"]}}) for k, v in {
                    "water": {"base": -3, "ground": "#2b5fa8", "water": True},
                    "grass": {"base": 0, "ground": "#5d9b3c", "side": "#6b4a2b", "bevel": [2, 1], "round": 5},
                    "trees": {"base": 7, "ground": "#2f6b2a", "side": "#4a3520", "bevel": [3, 2, 1], "round": 6,
                              "opaque": True},
                    "wall": {"base": 20, "ground": "#7b6f63", "side": "#5e554b", "opaque": True},
                    "floor": {"base": -1, "ground": "#b08a5a"},
                    "road": {"base": 0, "ground": "#c9b27c"},
                    "sign": {"base": 6, "ground": "#e0c040"},
                    "bridge": {"base": 0, "ground": "#8a5a2b"},
                    "prop": {"base": 0, "ground": "#2a2622"},
                }.items()},  # flat-colour art: every pixel takes its category colour
                "tiles": [[WATER, WATER, "water"], [GRASS, GRASS, "grass"], [TREES, TREES, "trees"],
                          [WALL, WALL, "wall"], [FLOOR, FLOOR, "floor"], [ROAD, ROAD, "road"],
                          [SIGN, SIGN, "sign"], [BRIDGE, BRIDGE, "bridge"]],
                "walk": {"categories": {}, "tiles": {str(t): True for t in sorted(WALKABLE)}},
                "sprites": {"pairs": [], "avatar": 67},
            },
            "dialogue": {str(VILLAGE): {
                "1": {"look": "a tired innkeeper", "NAME": "Bram, of the Crooked Kettle.",
                      "JOB": "I keep the inn. Mind the mice in the meadow.", "MICE": "Bold little things. Bring a stick.",
                      "BYE": "Safe roads."},
                "2": {"look": "a farmer leaning on a rake", "NAME": "Oda.", "JOB": "Turnips, mostly.",
                      "WISP": "The bog wisps sting. Stay on the road.", "BYE": "Mind the turnips."}}},
        },
    }


def check(doc: dict) -> list[str]:
    """Contract checks beyond the seeder's schema validation (the ones an adapter author gets wrong)."""
    seeder.validate(doc)
    maps = {m["id"]: m for m in doc["maps"]}
    walk = doc["walkable"]

    def ok(mid: int, x: int, y: int) -> bool:
        m = maps[mid]
        return 0 <= x < m["width"] and 0 <= y < m["height"] and walk[m["tiles"][y * m["width"] + x]]
    errs = []
    if 0 not in maps:
        errs.append("map 0 (the surface) is required")
    s = doc["spawn"]
    if not ok(s["map_id"], s["x"], s["y"]):
        errs.append("spawn is not walkable")
    for p in doc.get("portals", []):
        if not ok(p["from_map"], p["x"], p["y"]) or not ok(p["to_map"], p["to_x"], p["to_y"]):
            errs.append(f"portal {p['id']}: entry or arrival tile not walkable")
    for n in doc.get("npcs", []):
        if n["tile"] and not ok(n["map_id"], n["x"], n["y"]):
            errs.append(f"npc {n['map_id']}/{n['slot']} stands on an unwalkable tile")
    for r in doc.get("respawns", []):
        if not ok(r["map_id"], r["x"], r["y"]):
            errs.append(f"respawn {r['id']} not walkable")
    for mid, talks in doc.get("client", {}).get("dialogue", {}).items():
        refs = {n["talk"] for n in doc.get("npcs", []) if n["map_id"] == int(mid)}
        errs += [f"dialogue {mid}/{t} has no NPC" for t in talks if int(t) not in refs]
    if not any(k["kind"] == 0 for k in doc.get("item_kinds", [])):
        errs.append("item kind 0 (gold) is required: kills drop gold as kind 0")
    for e in doc.get("map_exits", []):
        if not maps[e["map_id"]].get("exit_at_edge"):
            errs.append(f"map {e['map_id']} has a map_exit but exit_at_edge is false")
    return errs


def sql(url: str, db: str, q: str) -> str:
    r = subprocess.run([*seeder.spacetime_cmd(), "sql", "--server", url, db, q], capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(f"sql failed: {r.stderr.strip()[-400:]}")
    return r.stdout


def count(url: str, db: str, table: str, where: str = "") -> int:
    out = sql(url, db, f"SELECT COUNT(*) AS n FROM {table} {where}")
    nums = [l.strip() for l in out.splitlines() if l.strip().isdigit()]
    return int(nums[-1]) if nums else -1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    w = sub.add_parser("write"); w.add_argument("out")
    lv = sub.add_parser("live"); lv.add_argument("--url", default="http://127.0.0.1:3000")
    lv.add_argument("--db", default="fixture-dev"); lv.add_argument("--publish", action="store_true")
    lv.add_argument("--godot", help="also run two Godot clients (--world, --route portal) against the fixture DB")
    lv.add_argument("--renderer", choices=["2d", "3d"], default="2d", help="client renderer for --godot")
    lv.add_argument("--shots", help="(needs a display) client 1 saves 2D+3D stills of both maps here; local only")
    lv.add_argument("--logs", help="retain complete Godot client output in this external evidence directory")
    a = ap.parse_args()
    doc = build()
    errs = check(doc)
    for e in errs:
        print("FIXTURE ERROR " + e)
    if errs:
        return 1
    if a.cmd == "check":
        print(f"FIXTURE PASS check maps={len(doc['maps'])} portals={len(doc['portals'])} npcs={len(doc['npcs'])}")
        return 0
    if a.cmd == "write":
        Path(a.out).write_text(json.dumps(doc), encoding="utf-8")
        print(f"wrote {a.out}")
        return 0
    if a.publish:
        rc = subprocess.call([sys.executable, str(ROOT / "tools" / "kit.py"), "publish", "--url", a.url, "--db", a.db,
                              "--module", str(SERVER)])
        if rc:
            return rc
    seeder.seed(doc, a.url, a.db)
    want = {"map_info": 2, "portal": 1, "map_exit": 1, "npc_meta": 3, "monster_kind": 2, "item_kind": 2,
            "safe_zone": 2, "respawn_point": 2}
    got = {}
    for t, n in want.items():
        try:
            got[t] = count(a.url, a.db, t)
        except SystemExit as e:
            got[t] = str(e)[:80]
    ok = all(got[t] == n for t, n in want.items())
    print(f"FIXTURE {'PASS' if ok else 'FAIL'} live db={a.db} rows={got}")
    if a.godot:
        ok = godot_route(a, doc) and ok
    return 0 if ok else 1


def godot_route(a, doc: dict) -> bool:
    """Two headless clients walk spawn -> village portal -> meet each other and the NPCs -> off the west edge."""
    import tempfile
    if not (CLIENT / ".godot").exists():  # fresh checkout: class_names resolve only after a first import
        subprocess.run([a.godot, "--headless", "--path", str(CLIENT), "--import"],
                       capture_output=True, timeout=300, check=True,
                       creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    world = Path(tempfile.mkdtemp(prefix="fixture-")) / "meadowmere.json"
    world.write_text(json.dumps(doc), encoding="utf-8")
    npcs = sum(1 for n in doc["npcs"] if n["map_id"] == VILLAGE)
    base = [a.godot, "--headless", "--max-fps", "60", "--path", str(CLIENT), "--", "--autopilot", "--route", "portal",
            "--world", str(world), "--url", a.url, "--db", a.db, "--seconds", "60", "--expect-npcs", str(npcs),
            "--renderer", getattr(a, "renderer", "2d")]
    procs = []
    outputs = []
    try:
        launches = []
        logs = Path(a.logs) if getattr(a, "logs", None) else world.parent
        logs.mkdir(parents=True, exist_ok=True)
        tag = os.urandom(2).hex()  # fresh identities each run; names are unique per server
        for i in (1, 2):
            shots = ["--shots", a.shots] if getattr(a, "shots", None) and i == 1 else []
            cmd = base + ["--name", f"Meadow{i}_{tag}"] + shots
            if shots:  # stills need a real display: drop --headless (run under xvfb-run on a server)
                cmd.remove("--headless")
            # Godot's user settings/logs are shared by project name unless the OS data root
            # is isolated. A fixture must never read a real player's settings or identity.
            env = dict(os.environ)
            user_root = (Path(a.logs) if getattr(a, "logs", None) else world.parent) / f"user-{i}"
            user_root.mkdir(parents=True, exist_ok=True)
            env.update(APPDATA=str(user_root), XDG_DATA_HOME=str(user_root), XDG_CONFIG_HOME=str(user_root))
            hidden = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
            launched = time.monotonic()
            output = (logs / f"client-{i}.log").open("w", encoding="utf-8")
            outputs.append(output)
            procs.append(subprocess.Popen(cmd, stdout=output, env=env,
                                          stderr=subprocess.STDOUT, text=True, **hidden))
            launches.append({"client": i, "pid": procs[-1].pid, "command": cmd,
                             "launch_seconds": time.monotonic() - launched, "started_at": time.time()})
            if getattr(a, "logs", None):
                (Path(a.logs) / "launches.json").write_text(json.dumps(launches, indent=2), encoding="utf-8")
            time.sleep(1.0)
        ok = True
        for i, p in enumerate(procs, 1):
            timed_out = False
            try:
                p.wait(timeout=120)
            except subprocess.TimeoutExpired:  # never leave a hung headless client behind
                for q in procs:
                    if q.poll() is None:
                        if os.name == "nt":
                            subprocess.run(["taskkill", "/PID", str(q.pid), "/T", "/F"],
                                           capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
                        else:
                            q.kill()
                        q.wait()
                timed_out = True
            outputs[i - 1].close()
            out = (logs / f"client-{i}.log").read_text(encoding="utf-8", errors="replace")
            if timed_out:
                out += "\nAUTOPILOT FAIL fixture client timed out"
            lines = [l for l in out.splitlines() if l.startswith(("AUTOPILOT", "SOURCE", "SCRIPT ERROR"))]
            print(f"[fixture client {i}] exit={p.returncode}\n  " + "\n  ".join(lines))
            ok &= (not timed_out and p.returncode == 0
                   and any(l.startswith("AUTOPILOT PASS") for l in lines)
                   and not any(l.startswith(("SCRIPT ERROR", "AUTOPILOT FAIL")) for l in lines))
    finally:
        for proc in procs:
            if proc.poll() is None:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                                   capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
                else:
                    proc.kill()
                proc.wait()
        for output in outputs:
            output.close()
    world.unlink()
    if getattr(a, "logs", None):
        world.parent.rmdir()
    print(f"FIXTURE {'PASS' if ok else 'FAIL'} godot route=portal world=meadowmere renderer={getattr(a, 'renderer', '2d')}")
    return ok


if __name__ == "__main__":
    sys.exit(main())
