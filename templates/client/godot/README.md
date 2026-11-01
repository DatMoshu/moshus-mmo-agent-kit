# Godot 4.7 client starter

**Status: VERIFIED headless.** Two Godot 4.7.2 instances (and earlier 4.6.3) joined a SpacetimeDB 2.14.0 server
and each saw the other move (`python tools/kit.py smoke --godot`). It uses the vendored
[flametime Godot SpacetimeDB SDK](https://github.com/flametime/Godot-SpacetimeDB-SDK)
(MIT, plugin 0.3.2) in `addons/SpacetimeDB/`.

## Layout

* `net/net_session.gd` (autoload `Net`) is **the only file that talks to the SDK.** Game code
  calls `Net.connect_to_server`, `Net.join`, `Net.send_move`, `Net.my_transform()` and
  `Net.visible_transforms()`. If you swap or upgrade the SDK, only this file changes.
* `scenes/main.gd` is a minimal playable scene (squares and names, WASD/arrows) plus an
  `--autopilot` mode used by the smoke test.
* `spacetime_bindings/schema/` holds the generated bindings for
  `templates/server/rust-single`, committed so the project opens without any setup.
* `tools/codegen.gd` regenerates the bindings headlessly
  (`python tools/kit.py bindings` with `GODOT` set).

## SDK lessons (each one cost a debugging session)

1. **`client.db` is null until connected.** Register table callbacks inside the `connected`
   handler, not in `_ready`.
2. **Unsubscribing does not delete cached rows.** Use one subscription per AOI cell
   (non-overlapping), subscribe to the new cells *before* you drop the old ones, and filter
   reads by the current cell set (`visible_transforms()` does this).
3. **Identity persistence:** `one_time_token = true` (the SDK default) gives a fresh identity
   every run. Pass `--profile NAME` to store a token per profile under `user://`.
4. **Names are unique and persist.** `join` returns the error text ("name taken"), so show it
   to the player.
5. After regenerating bindings, run `godot --headless --import` once so the class cache
   picks up the new scripts.

## Run

Open the folder in Godot 4.7 and press Play twice (Debug > Customize Run Instances).
Headless:

```bash
godot --headless --path . -- --autopilot --url http://127.0.0.1:3000 --db mmo-dev --dir 1,0 --seconds 8
```

The other options are `--name`, `--profile`, and `--expect-peers N`.
