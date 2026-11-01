class_name Game
## The game hook: the ONLY client file the core (scenes/, net/, render/, ui/, core/) asks for game-specific
## behaviour. Each game ships its own copy. This template's runs a mmo-core-world/1 document (--world FILE,
## e.g. the Meadowmere fixture from tools/shard/fixture_game.py). A game that reads its world some other way
## returns its own TileSource subclass from make_source (see docs/SHARD_CORE.md).


static func title() -> String:
	return "MMO Shard"


static func make_source(args: Dictionary) -> TileSource:
	var ds := DocSource.new()
	if ds.load_doc(String(args.get("world", ""))):
		print("SOURCE source=%s game=%s root=%s" % [ds.source, ds.game, ds.root])
	else:
		push_warning(ds.error)
		print("SOURCE source=none (%s)" % ds.error)
	return ds


## The game's own HUD (a Hud subclass overriding Hud.FACADE; see docs/SHARD_CORE.md "UI hooks"), or null for the
## core HUD. Called once from main._ready, before the first renderer and extend().
static func make_hud(_main: Node) -> Hud:
	return null


## Extra per-game UI/logic attached to the main scene (none for the template). Called once from _ready.
static func extend(_main: Node) -> void:
	pass


## Called every frame while joined, before the core's own autopilot/input. Return true when the game
## drove this frame itself (its own --route, a modal panel); the core then skips movement input and
## its built-in routes (rendering and the HUD still run).
static func process(_main: Node) -> bool:
	return false


## Called after the core built each frame's view from server rows: add game-specific markers (spell effects,
## status hints) to `st.items` / `st.monsters` names. Renderers draw whatever is there; no new renderer code.
static func decorate_view(_main: Node, _st: MapViewState) -> void:
	pass


## Where --bench starts its overworld loop: the middle of map 0.
static func bench_start(src: TileSource) -> Vector2:
	return Vector2(src.map_size(0)) / 2.0
