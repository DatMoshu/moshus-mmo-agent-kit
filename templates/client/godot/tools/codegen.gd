## Headless bindings generator for the vendored GDScript SDK (no editor UI needed).
##   godot --headless --path . --import
##   godot --headless --path . -s res://tools/codegen.gd -- --schema <schema.json> [--module mmo]
## Get the schema with:  GET <server>/v1/database/<db>/schema?version=10  (tools/kit.py bindings does this).
extends SceneTree

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var schema_path := ""
	var module := "mmo"
	for i in args.size():
		if args[i] == "--schema" and i + 1 < args.size():
			schema_path = args[i + 1]
		elif args[i] == "--module" and i + 1 < args.size():
			module = args[i + 1]
	if schema_path.is_empty():
		printerr("usage: -s res://tools/codegen.gd -- --schema <schema.json> [--module mmo]")
		quit(2)
		return
	var cfg: SpacetimeDBPluginConfig = load(SpacetimePlugin.SAVE_PATH)
	if cfg == null or not cfg.module_configs.has(module):
		printerr("module '%s' not found in %s" % [module, SpacetimePlugin.SAVE_PATH])
		quit(3)
		return
	cfg.module_configs[module].unparsed_module_schema = FileAccess.get_file_as_string(schema_path)
	var codegen := SpacetimeCodegen.new(SpacetimePlugin.BINDINGS_SCHEMA_PATH)
	codegen._plugin_config = cfg
	var files := codegen.generate_bindings()
	print("generated %d files" % files.size())
	quit(0 if files.size() > 0 else 4)
