## MapRenderer: the swappable view. main.gd builds a MapViewState from server state each frame and
## calls render(); a renderer owns its own nodes (2D canvas or 3D scene) and nothing else.
## Implementations: TileRenderer2D ("2d", classic tiles, M1) and VoxelRenderer3D ("3d", voxel diorama).
## main.gd keeps one instance of each kind it has used and switches with set_active() (Tab / F3) mid-session;
## renderers never touch networking (net/) or game state, so switching cannot affect the connection.
class_name MapRenderer
extends Node

var tiles: TileSource


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
