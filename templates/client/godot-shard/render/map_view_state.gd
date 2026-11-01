## MapViewState: everything a map renderer may draw, built from server state each frame.
## Renderers read ONLY this (plus the TileSource); they never touch networking or game rules.
class_name MapViewState
extends RefCounted

var map_id := -1
var focus := Vector2.ZERO        # tile-space point to centre the view on (usually me)
var entities: Array[Dictionary] = []  # {id: String, name: String, pos: Vector2, is_me: bool, moving: bool, hp: int, max_hp: int}
var npcs: Array[Dictionary] = []      # {id: int, tile: int, pos: Vector2}
var monsters: Array[Dictionary] = []  # {id: int, tile: int, pos: Vector2, name: String, hp: int, max_hp: int}
var items: Array[Dictionary] = []     # {id: int, tile: int, pos: Vector2 (tile centre), name: String, qty: int}
var target_id := -1                   # the monster the player is fighting (highlighted), -1 = none
var visibility = null            # optional LOS result (e.g. PackedByteArray mask); null = all visible
