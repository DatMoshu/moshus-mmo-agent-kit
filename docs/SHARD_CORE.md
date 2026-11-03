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
| `npcs` | `[{map_id, slot, tile, x, y, wander, talk}]` | server-simulated; `talk` is an opaque per-map u16 dialogue reference (0..65535; 0 = none), validated before any seed mutation |
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
func atlas() -> Texture2D               # 16x16 grid of 16-px tiles, indexed by tile id (the source's own art)
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

Input remapping (a game's own key scheme, set from `extend(main)`): `main.key_hook: Callable(InputEventKey) -> bool`
sees every key press before the core keys (return true to consume it); `main.move_hook: Callable(Vector2i) ->
Vector2i` rewrites the frame's walking direction; `main.wasd_enabled = false` leaves only the arrows so W/A/S/D
can be commands; `main.move_dir()` is the resulting direction. Neither hook runs while a HUD text box has focus.

### UI hooks (renderers and HUD)

Every `MapRenderer` (2D `TileRenderer2D`, 3D `VoxelRenderer3D`) offers the same additive hooks for a game's
own UI layer. None changes what is drawn unless used.

```gdscript
var external_tags := false          # true: the renderer skips its own name labels / HP bars (the UI draws them)
var last_state: MapViewState        # the frame's view (focus, entities) after render(); null before the first
var screen_offset: Vector2          # read-only; set with set_screen_offset()
func world_to_screen(tile: Vector2, height := 0.0) -> Vector2   # viewport px of a tile-space point; NAN = not visible
func screen_to_world(screen: Vector2) -> Vector2                # tile-space point under a viewport px; NAN = none
func set_screen_offset(px: Vector2) -> void   # shift the map's drawn centre by px (e.g. right of a side panel)
func refresh_atlas() -> void                  # re-read TileSource.view_atlas*() (main calls it on a tileset switch)
```

* 2D: `world_to_screen` also returns points off the window (callers clip); the visible tile range is
  computed from the offset viewport, so any offset leaves no undrawn strip.
* 3D: the offset is applied as camera `h_offset`/`v_offset` (both axes). `world_to_screen(tile, height)` takes
  the height in tiles above ground and includes the world curvature; it returns NAN behind the camera or outside line of sight.
  `screen_to_world` ray-marches the curved terrain surface (category heights from the voxel table plus the
  curvature drop) with a final bisection, so it is exact to the tile on flat categories. **Limit:** per-pixel
  bevels, bumps and `dh` rules (< 1/4 tile) are ignored, and on the wrapping overworld it returns the copy
  nearest the camera focus (unwrapped coordinates; wrap with `posmod` if needed).

The HUD is replaceable. **Hook:** `static func make_hud(main: Node) -> Hud` in `client/game/game.gd`
(optional; return null, or leave it out, for the core HUD) is called once in `main._ready` before the first
renderer and `Game.extend`; main looks it up dynamically, so a game.gd written before the hook still compiles.
The core `Hud` is only constructed when the hook is missing or returns null (nothing is built and thrown
away), and a `Hud` frees any of its default widgets that never got a parent when it is deleted, so a subclass
that skips `super._ready()` leaves no orphan nodes at exit.
At run time `main.set_hud(h: Hud)` swaps HUDs: it frees the current one and installs `h`, keeps its visibility, reconnects the three signals (`chat_submitted`, `talk_submitted`,
`talk_closed`) and emits `main.hud_changed(h)`. The replacement `extends Hud`, does **not** call
`super._ready()` (so the default widgets are never built) and overrides every method in `Hud.FACADE`:
`is_typing() -> bool`, `open_chat()`, `close_inputs()`, `toggle_help()`, `toast(text, seconds := 2.5)`,
`show_talk(title, text, focus := true)`, `end_talk()`, `talk_text() -> String`, `update(d: Dictionary)`. `update` receives
`{name, hp, max_hp, level, xp, gold, kills, deaths, map, renderer, tileset, inventory, chat}` every frame.
Nothing in the core needs to change for a game's own UI; `client/game/` is the only place it lives.

### Tilesets (switchable art packs)

The server only ever sends tile ids (0-255); art is a client choice. A **tileset pack** replaces the tile art
in both renderers at run time. Core files: `render/tileset_pack.gd` (`TilesetPack`: manifest validation,
building), `render/tilesets.gd` (`Tilesets.discover`), `TileSource` (active pack, game-specific packs) and
`scenes/main.gd` (switching, keys, setting).

**Player side.** F4 next pack, Shift+F3 previous pack (Shift+F4 is the 3D renderer's grid toggle; plain
F3 / Tab still switch 2D / 3D) (a toast shows name and credit; the HUD status line shows the
active pack). The choice is saved as `render/tileset` in `user://settings.cfg` (load-modify-save, other keys
kept). `--tileset ID` picks the start pack (overrides the setting); `--tileset-dir DIR` adds a folder of packs
besides `user://tilesets/` (one sub-folder per pack: `user://tilesets/<id>/tileset.json` + images). Folders
that fail validation are skipped with one `TILESET skip dir=… <reasons>` line; each loaded pack prints
`TILESET id=… cell=… mapped=N/256 anim=K`.

**Manifest** (`tileset.json`, schema 1):

```json
{"schema": 1, "id": "my-pack", "name": "My pack", "platform": "community",
 "tile_size": [16, 16], "fit": "stretch", "palette": "embedded",
 "source": {"kind": "pack", "sheets": [{"file": "tiles.png", "columns": 16}]},
 "mapping": {"kind": "table", "table": {"0-63": 0, "64": [64, 65]}, "fps": 4},
 "fallback": "default", "voxel_colour": "ega", "credit": "...", "licence": "...", "url": "..."}
```

* Required: `schema`, `id` (`^[a-z0-9][a-z0-9-]{1,47}$`), `name`, `platform` (`community` or one of the
  game's `TileSource.tileset_platforms()`), `tile_size` ([w, h], 4-256 px), `source`.
* `source.kind`: `pack` (sheets cut left-to-right, top-to-bottom; `file` relative, no `..`; `columns` >= 1;
  several sheets concatenate) or `install` (`extractor`: the game's `TileSource.extract_tileset(extractor, path)`
  decodes the player's own files at run time).
* `mapping.kind`: `identity` (raw tile n = tile id n) or `table`: keys are tile ids `"N"` or ranges `"A-B"`,
  values a raw index (a range maps A+j -> v+j) or a list of raw indices = animation frames (`fps`, default 4;
  for a range every frame index is offset by j).
* `fit`: `stretch` (default) or `pad` (centre on black, keeps the aspect, e.g. 14x16 art).
  `palette`: `embedded` (use the PNG's colours), `ega`, `cga` or a list of hex colours (pixels snap to the
  nearest).
* Unmapped tile ids are drawn from the `fallback` pack (default: the game's own art, id from
  `TileSource.default_tileset_id()`), else a magenta placeholder. `mapped=N/256` reports coverage.
* The built atlas is 16 columns of `cell` px tiles, `cell = clamp(max(tile_size), 16, 64)`; animation frames
  are extra rows after tile 255.
* `voxel_colour`: `ega` (default: the 3D terrain keeps the base art's colours and only sprites/billboards use
  the pack) or `sample` (the voxel terrain takes the pack's pixels, snapped to the 16-colour table; the voxel
  table's per-pixel `colour` overrides are then ignored, heights and flags still apply). The 3D option
  `packcol` forces sampling for every pack, `packsprites=false` keeps base-art sprites.

**Game side** (`TileSource`, all optional):

```gdscript
func default_tileset_id() -> String          # id of the source's own art ("default"); e.g. "dos-ega"
func default_tileset_name() -> String        # "Default"
func default_tileset_meta() -> Dictionary    # {platform, credit, licence, url} of the own art
func builtin_tilesets() -> Array[TilesetPack] # packs decoded from the player's install (TilesetPack.from_image)
func extract_tileset(extractor, path) -> Image   # for source.kind = install
func detect_tileset(dir) -> Dictionary       # a manifest for a folder without tileset.json (community layouts)
func tileset_platforms() -> PackedStringArray    # accepted platform ids besides "community"
```

The renderers draw through `view_atlas()`, `view_atlas_image()`, `view_tile_rect(tile)` and `view_cell()`
(the active pack, animated). `atlas()`, `atlas_image()` and `tile_rect()` stay the source's own art (16 px
grid): game code and the voxel profile table keep their meaning whatever pack is active.

**API** on main: `set_tileset(id, persist := true) -> bool` (false for an unknown id), `cycle_tileset(step := 1,
persist := true) -> String`, `tileset_list() -> Array[Dictionary]` (`{id, name, platform, credit, licence, url,
builtin, dir, cell, mapped, animated, voxel_colour, active, preview}`; `preview` is an optional `Texture2D`
of 4x4 tiles at the pack's cell size, absent when a pack has no art; the 16 tile ids come from an optional
`TileSource.preview_tiles() -> PackedInt32Array`, default 0..15), `tileset_id() -> String`, signal `tileset_changed(id)`. The setting is never saved
in `--autopilot`, `--bench` or `--tileset-check` runs.

**Check.** `python tools/shard/tileset_check.py --project CLIENT [--renderer 2d|3d|both] [--shots DIR] -- <source
flags>` writes synthetic packs (generated coloured squares, safe to share: 16 px identity, 32 px table with an
animation and fallback, 14x16 pad with EGA snapping, plus two folders that must be refused) and runs the
client offline with `--tileset-check --tileset-dir DIR --tileset-expect IDS`: every pack must build a 256-tile
atlas, become the renderers' atlas, render, and `cycle_tileset(1)` / `cycle_tileset(-1)` (F4 / Shift+F3) must cycle all packs in order and wrap; with a
display each pack's frame must differ. The same run checks the UI hooks: for screen offsets (0,0), (200,-120)
and (-150,90) the focus must project to the offset centre and `screen_to_world` must invert `world_to_screen`
(2D at height 0.5, the point drawn at p; 3D at height 0, skipping points out of line of sight). `tileset_check.py write DIR` only writes the packs.

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
