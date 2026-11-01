# KIT-007: The shard core lives in the kit and games vendor it

- Status: accepted
- Date: 2026-11-01

## Context
The tile-world MMO core (server `core/`, the Godot client's core/net/render/ui/scenes, `tools/shard`) was
built inside one game repo and is meant to carry several classic top-down RPG shards. Game repos are
local-only (no remotes), so git submodules or a package registry would add moving parts with nothing to
pull from. Each game must still be able to prove its core is unmodified, and a core change must be tested
against a world the kit can ship: the code-generated Meadowmere fixture, which contains no third-party
game data.

## Decision
The core lives in the kit as `templates/server/rust-shard`, `templates/client/godot-shard`, `tools/shard`
and `docs/SHARD_CORE.md` / `docs/VOXEL_TABLE.md`. Game repos copy it verbatim with
`tools/shard/vendor_core.py --from KIT_DIR`, which writes `CORE_VENDOR.json` (kit commit and a sha256
per file); `vendor_core.py --check` fails on any local edit. Games add behaviour only through their own
files (`client/game/game.gd`, a game folder with a `TileSource` subclass and voxel table, server modules
beside `core/`, their own tools).

## Consequences
- A core fix is made once in the kit, tested with Meadowmere (2D and 3D, two clients), then re-vendored.
- Games can build offline and from a single checkout; there is no submodule or package step.
- A game that needs a new hook asks for it in the kit (an additive change to `Game`/`TileSource` or the
  world document), never by patching vendored files.
- Re-vendoring is manual; `--check` in each game's test run catches drift.
