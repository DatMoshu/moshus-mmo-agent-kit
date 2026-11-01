# godot-shard: Godot 4.7 client for the shard core

**Status: VERIFIED headless and under Xvfb.** Two Godot 4.7.2 clients join the `rust-shard` module, walk the
Meadowmere fixture through a portal into town and back, see each other, NPCs and monsters, in the 2D tile
renderer and the 3D voxel diorama (`python tools/shard/fixture_game.py live --godot $GODOT --renderer 2d|3d`).

## Layout

| Folder | Role | Edit? |
|---|---|---|
| `net/` | `Net` autoload, the only file that talks to the SpacetimeDB SDK | core (vendored) |
| `core/` | `DocSource` (reads a `mmo-core-world/1` document), conversation/keyword talk | core |
| `render/` | `TileSource` API, 2D tile renderer, `palette.gd`, `voxel/` 3D diorama (table-driven, see `docs/VOXEL_TABLE.md`) | core |
| `ui/` | HUD, chat, talk panel | core |
| `scenes/` | `main.gd`: glue, input, autopilot routes used by the tests | core |
| `game/game.gd` | **The game hook**: title, `make_source`, `extend`, `process`, `bench_start`, `decorate_view` | yours |
| `spacetime_bindings/` | generated bindings for `templates/server/rust-shard` (regenerate with `python tools/kit.py bindings`) | generated |

A game adds its own folder (for example `client/mygame/`) with a `TileSource` subclass and returns it from
`Game.make_source`. Its voxel look is a JSON table the source returns from `voxel_table()`; the core ships a
neutral default in `render/voxel/tile_profiles.json`.

Useful flags (after `--`): `--world FILE`, `--name`, `--profile`, `--renderer 2d|3d` (or `SHARD_RENDERER`),
`--autopilot --route portal`, `--shots DIR`, `--bench`.

SDK lessons from the `godot` template README apply unchanged (connect before table callbacks, one
subscription per AOI cell, `--profile` for persistent identity, unique names).
