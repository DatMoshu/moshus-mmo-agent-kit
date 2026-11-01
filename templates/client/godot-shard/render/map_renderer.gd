## MapRenderer: the swappable view. main.gd builds a MapViewState from server state each frame and
## calls render(); a renderer owns its own nodes (2D canvas or 3D scene) and nothing else.
## Implementations: TileRenderer2D ("2d", classic tiles, M1) and VoxelRenderer3D ("3d", voxel diorama).
## main.gd keeps one instance of each kind it has used and switches with set_active() (Tab / F3) mid-session;
## renderers never touch networking (net/) or game state, so switching cannot affect the connection.
class_name MapRenderer
extends Node

var tiles: TileSource

## UI hook: when true the renderer leaves entity name labels and HP bars to a screen-space tag layer of the
## game's UI (which reads last_state and places tags with world_to_screen); map, sprites and target marker stay.
var external_tags := false
## The last state passed to render() (read-only; UI layers read entity names and positions from it).
var last_state: MapViewState
## UI hook: shift the drawn map by this many viewport pixels (a HUD covering one side of the screen keeps the
## player centred in the visible part). Zero = unchanged behaviour. Set it with set_screen_offset().
var screen_offset := Vector2.ZERO


## Called once with the tile loader (may have no data: renderers must draw placeholders).
func attach(source: TileSource) -> void:
	tiles = source


## Called every frame with the current view (only on the active renderer).
func render(_state: MapViewState) -> void:
	pass


## Show / hide everything this renderer owns (it stays attached and keeps its caches while hidden).
func set_active(_on: bool) -> void:
	pass


## Renderer-specific options (e.g. from the command line); unknown keys are ignored.
func configure(_opts: Dictionary) -> void:
	pass


## True once the current view is fully drawn (e.g. 3D chunks built); screenshots and benches wait for it.
func is_ready() -> bool:
	return true


## UI hook: viewport pixel position of a tile-space point, `height` tiles above the ground under it
## (height 1.0 = top of a standing sprite). Vector2(NAN, NAN) when there is no projection (3D: behind the camera or
## out of line of sight; no map yet). Points off the window are returned as they are: the caller clips.
func world_to_screen(_tile: Vector2, _height := 0.0) -> Vector2:
	return Vector2(NAN, NAN)


## UI hook: tile-space point on the ground under a viewport pixel; Vector2(NAN, NAN) when there is none.
func screen_to_world(_screen: Vector2) -> Vector2:
	return Vector2(NAN, NAN)


## UI hook: see screen_offset.
func set_screen_offset(px: Vector2) -> void:
	screen_offset = px


## The TileSource's active tileset changed (main.set_tileset): re-read view_atlas() and redraw.
func refresh_atlas() -> void:
	pass


## One-line HUD text: renderer name and its toggles.
func describe() -> String:
	return ""


static func create(kind: String) -> MapRenderer:
	match kind:
		"2d", "":
			return TileRenderer2D.new()
		"3d":
			return VoxelRenderer3D.new()
		_:
			push_warning("unknown renderer '%s', using 2d" % kind)
			return TileRenderer2D.new()
