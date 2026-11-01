# Shard core: the adapter contract

This project is built on the **shard core** from Moshu's MMO Agent Kit (`templates/server/rust-shard` +
`templates/client/godot-shard` + `tools/shard/`): a game-agnostic tile MMO on SpacetimeDB. The core never
names a game; a game **adapter** turns one game's data into the core's two inputs: a **world document** for
the server and a **TileSource** for the client. Meadowmere (`tools/shard/fixture_game.py`) is the synthetic
reference adapter; it ships with the core and is its test.

| Layer | Core (game-agnostic, vendored) | A game adds |
|---|---|---|
| Server | `server/src/core/*` (collision, body blocking, NPC wander, chat, PvE combat, items, persistence, seed reducers) | `server/src/lib.rs` (+ optional `server/src/<game>/` for game rules) |
| Seeding | `tools/shard/seeder.py` (validates + sends an `mmo-core-world/1` document) | `tools/<game>/<game>adapter.py` (builds the document) |
| Client tiles/art | `client/render/tile_source.gd` (interface), `client/core/doc_source.gd` (from a document) | `client/<game>/<game>_local.gd` (reads the player's install) |
| Client dialogue | `client/core/conversation.gd`, `client/core/keyword_talk.gd`, `client/ui/hud.gd` | a `Conversation` subclass if keywords are not enough |
| Client glue | `client/net/`, `client/render/` (2D + 3D voxel), `client/ui/`, `client/scenes/main.gd`, `client/render/palette.gd` | `client/game/game.gd` (`Game.make_source`, `Game.extend`, `Game.process`, `Game.bench_start`, `Game.decorate_view`) |
| 3D | `client/render/voxel/*` + the generic `tile_profiles.json` | a voxel table (docs/VOXEL_TABLE.md) via `TileSource.voxel_table()` |
| Tests | `fixture_game.py check` / `live [--godot]` | the game's own route/play checks |

The vendored file list and hashes are in `CORE_VENDOR.json` (see "Vendoring" below).

### Game-layer hooks on the server

A game's own module (`server/src/<game>/`) builds on the core without editing it:

- `player_mods` (public table, one optional row per player): `dmg_bonus` (added to melee), `armour`
  (subtracted from damage taken, minimum 1), `level_cap` (0 = none; XP keeps accruing but automatic
  level-ups stop at the cap; raise it and call `combat::apply_level` to promote).
- `combat::damage_monster(ctx, who, monster_id, dmg)` — damage with kill credit (spells, traps);
  `damage_monster_as(.., kind)` tags the combat event (`COMBAT_SPELL`, or a game kind from 16 up).
- `combat::spawn_monster(ctx, map, x, y, kind)` / `combat::move_monster(ctx, id, x, y)` — summons, knock-back, scripted encounters (caller checks the tile).
- `combat::hurt_player` / `hurt_player_by(.., src_monster, kind)`, `combat::combat_event` (record a heal or
  effect yourself), `chat::deliver(ctx, from, to, channel, target_name, text)` (party / system lines into
  a player's private `my_chat`), `movement::place` (teleport/map change with AOI bookkeeping), `combat::mods_of`.
- `combat::set_status(ctx, monster_id, ai::STATUS_*, ticks)` / `combat::clear_statuses` — timed monster
  statuses for spells: `STATUS_SLEEP` (skips turns, damage wakes it), `STATUS_CONFUSE` (fights the nearest
  other monster), `STATUS_SILENCE` (no ranged attacks), `STATUS_FEAR` (runs away). The public
  `monster_status` table lets clients draw them. `combat::behaviour_of(kind)` reads a kind's behaviour
  (games keep their own per-kind flags in the high 16 bits of `flags`, e.g. "undead").

### Client-facing data the core publishes (for UIs)

| Data | Where | Notes |
|---|---|---|
| XP for the next level | public `level_xp {level, xp, max_hp}` (levels 1..100) | next = `level_xp[player_stats.level + 1].xp`; a game's `level_cap` still applies |
| Chat channel | public `chat_channel {id, channel}` side table of `chat_message` | no row = world (1); `say_in(channel, text)` with 0 local / 1 world; `say(text)` = world |
| Whispers, party, system lines | private `chat_direct` via the `my_chat` view | `whisper(to_name, text)` (sender gets a copy, `target_name` = recipient); games call `chat::deliver`; channel 2 party, 3 system, 4 whisper; last 50 per reader |
| Damage numbers | public `combat_event` (last 256; index on `map_id`) | src/dst player identity or monster id, `amount` actually dealt, `kind` 0 melee / 1 spell / 2 heal / 3 other, `flags` 1 killed a monster / 2 player died, `tick` |

### Monster behaviour (data-driven, `core/ai.rs`)

Each monster kind may carry an `ai` object (seeded with `seed_monster_ai`; no object = melee brute):

| Field | Meaning |
|---|---|
| `flee_hp_pct` | runs from its target at or below this % of max HP (0 = never); fights back when cornered |
| `range` | ranged attack reach in tiles (0/1 = melee only); uses the kind's damage and attack ticks; no line-of-sight test |
| `keep_dist` | a ranged attacker steps back while the target is closer than this |
| `pack` | radius: when one engages or is hit, kin of the same kind in the radius join in on that player (10 s alert) |
| `flags` | bit 0 `AI_STATIONARY` (never steps), bit 1 `AI_NO_HOME` (no leash, no drifting home); bits 16-31 game-defined |

The decision (`ai::decide`) is a pure function with unit tests (`cargo test --lib ai`).

## 1. Server: the `mmo-core-world/1` document

One JSON document; `tools/shard/seeder.py` is the reference (`validate(doc)` raises on any contract error,
`seed(doc, url, db)` sends it). Reducer order: `seed_begin(source kind, tag)` → `seed_tile_rules` →
`seed_map` + `seed_chunk`… → portals, exits, NPCs, spawn rules, safe zones, respawns, item kinds →
`seed_commit`. Seed reducers are admin-only (the identity that published the module). Re-seeding replaces
the world content (maps, portals, NPCs, rules) and is safe to repeat; player rows (identity, position, stats,
inventory) are kept, and a player whose saved tile is no longer walkable is moved to the spawn on join.

| Key | Shape | Meaning |
|---|---|---|
| `format` | `"mmo-core-world/1"` | contract version; bump on a breaking change only (schema changes are additive) |
| `game`, `source` | `str`, `{kind, tag}` | `kind` = install / fixture / …; `tag` = content hash (seed idempotency) |
| `walkable` | `bool[256]` | per tile id; the server's only notion of terrain |
| `maps` | `[{id, key, width, height, tiles[w*h], exit_at_edge}]` | sizes are multiples of 32 (chunking); `key` is what the client's TileSource loads |
| `map_exits` | `[{map_id, to_map, x, y}]` | walking off the edge of `map_id` (needs `exit_at_edge`) puts you at `to_map:x,y` |
| `portals` | `[{id, name, from_map, x, y, to_map, to_x, to_y}]` | stepping on `from_map:x,y` teleports (towns, moongates, ladders) |
| `npcs` | `[{map_id, slot, tile, x, y, wander, talk}]` | server-simulated; `talk` is an opaque per-map dialogue reference for the client (0 = none) |
| `monster_kinds` | `[{kind, name, tile, hp, dmg_min, dmg_max, step_ticks, attack_ticks, aggro, xp, gold_min, gold_max, ai?}]` | `ai` = optional `{flee_hp_pct, range, keep_dist, pack, flags}` (see "Monster behaviour") |
| `spawn_rules` | `[{id, map_id, max_alive, kinds[], min_dist, max_dist}]` | monsters spawn around players, outside safe zones |
| `safe_zones` | `[{id, map_id, x, y, r}]` | no spawning, no combat (Chebyshev radius) |
| `respawns` | `[{id, map_id, x, y}]` | where the dead return (nearest on the same map, else the lowest id) |
| `item_kinds` | `[{kind, name, tile, heal}]` | **kind 0 must be gold** (kills drop gold as kind 0) |
| `spawn` | `{map_id, x, y}` | new players |
| `client` | any | optional, ignored by the server (DocSource colours + dialogue) |

Invariants the seeder or `fixture_game.check()` enforce: map 0 exists (the surface); spawn, portal ends,
NPC tiles and respawns are walkable; ids are unique; `map_exits` only on `exit_at_edge` maps.

**Stable ids.** Map 0 = surface, map 1 = the "home town" the scripted routes target (e.g. Meadowmere: Hollow). Route tests find the portal *into* map 1 (`Net.portal_into(1)`), so keep that id stable.


## 2. Client: `TileSource` (+ `Conversation`) and `Game`

```gdscript
class_name TileSource extends RefCounted
var root, source, maps, error, player_tile   # diagnostics + map_id -> {w, h, tiles, key}; hero sprite id
func tile_at(map_id, x, y) -> int       # -1 outside / unknown
func map_size(map_id) -> Vector2i
func atlas() -> Texture2D               # 16x16 grid of 16-px tiles, indexed by tile id
func atlas_image() -> Image             # the same pixels on the CPU (3D voxelizer, headless)
func register_map(map_id, key, w, h) -> bool   # called for every server map_info row
func start_talk(map_id, talk) -> Conversation  # null = nothing to say
func walk_table() -> PackedByteArray   # optional; client-side pathing for scripted routes
func voxel_table() -> Dictionary       # optional; {} = the generic table
```

`Conversation` is `open() -> String`, `reply(text) -> String`, `title`, `done`. The HUD drives it; nothing
is sent to the server (dialogue stays on the player's machine).

`client/game/game.gd` (`class_name Game`) is the only client file the core calls for game behaviour:
`make_source(args) -> TileSource` (the template: `--world FILE` → `DocSource`), `extend(main)` (attach game
UI/logic once, after the first renderer is up), `process(main) -> bool` (each joined frame; true = the game
drove it, so the core skips its input/autopilot), `bench_start(src) -> Vector2` (where `--bench` walks),
`decorate_view(main, st)` (add game markers such as spell fields to the frame's view), `title()`. Source loaders print one `SOURCE source=… root=…` line (the test harnesses read it).

## 3. Rules for an adapter whose data is commercial

* The repo ships **code only**. The adapter reads the player's install at run time; derived output goes to
  a gitignored folder. Keep a repo scanner (no game bytes, names lists, dialogue, or GPL code in a commit).
* Format knowledge comes from published documentation, written down in the adapter's FORMAT_NOTES. GPL
  engines are behaviour references only: no code is read for porting, copied, or translated.
* The server receives only what the document carries (tile ids, positions, numbers, short names).

## 4. Starting the next game (checklist)

1. Copy `tools/shard/fixture_game.py` to `tools/<game>/<game>adapter.py`; replace `build()` with a reader
   for the game's files (keep `check()`); write the formats you rely on into `tools/<game>/FORMAT_NOTES.md`.
2. Run it `live --godot` with `--world` first (flat colours, KeywordTalk) to play before any art loader exists.
3. Add `client/<game>/<game>_local.gd` (TileSource) for real tiles and point `Game.make_source` at it; add a
   `Conversation` subclass if the game's dialogue model differs from keywords.
4. 3D: give the TileSource a voxel table (docs/VOXEL_TABLE.md).
5. Write the game's route/play checks (the client's `--route portal` / `--route play` autopilots are generic).

## Vendoring

Game repos copy the core files verbatim and record them in `CORE_VENDOR.json` (kit commit + sha256 per
file). `python tools/shard/vendor_core.py --check` fails when a vendored file was edited locally;
`python tools/shard/vendor_core.py --from KIT_DIR` refreshes them from a kit checkout. Change core behaviour
in the kit first (with its Meadowmere tests), then re-vendor. Game code never lives in vendored paths. Why vendoring and not a submodule: `docs/adr/KIT-007-shard-core-vendored.md` (in the kit).
