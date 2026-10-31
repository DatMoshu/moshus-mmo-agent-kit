---
name: stdb-bindings-regen
description: Regenerate and verify client bindings for every client (TypeScript, Godot, C#, Unreal) after a module change. Use after every publish that changes tables, reducers or types.
---

# Bindings regeneration

## Command

```
python tools/kit.py bindings          # TS for bots and web admin; Godot if GODOT is set and the server runs
python tools/kit.py bindings --check  # CI: fail if the committed Godot bindings differ (ignoring pure reordering)
```

The tool runs these, at the version in `stdb.lock`:

- **TypeScript:** `spacetime generate --lang typescript --out-dir <client>/src/module_bindings --module-path <module> --yes`.
  Set `KIT_WASM` to generate from a prebuilt `.wasm` with `--bin-path`.
- **Godot (flametime GDScript SDK):** fetches `/v1/database/<db>/schema?version=10` from the running server, then
  runs `godot --headless -s res://tools/codegen.gd -- --schema <file>`, then `godot --headless --import`.
- **C# / Unity:** `spacetime generate --lang csharp --out-dir <Assets/...>/module_bindings --module-path <module>`.
- **Unreal:** see `skills/vendor/official/unreal/SKILL.md` for the codegen target at the pinned version.

## Rules

- Regenerate after **every** publish that changes the schema. Stale bindings cause deserialization errors and missing
  reducers at runtime.
- Never hand-edit generated files. Regenerate instead.
- Commit generated bindings for engine clients (Godot, Unity) so a fresh clone opens without a server. The TS bot
  bindings are generated on demand and gitignored.
- After Godot codegen, run `--import` so new `class_name`s are registered.
