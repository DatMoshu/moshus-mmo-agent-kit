---
name: stdb-godot-client
description: Build a Godot 4.6 client for a SpacetimeDB world with the community flametime GDScript SDK (net facade, AOI subscriptions, identity profiles, headless smoke tests). Use for any Godot client work.
---

# Godot client

The reference is `templates/client/godot`, which is verified headless (`python tools/kit.py smoke --godot`).

## Architecture

- **One facade:** `net/net_session.gd` (autoload `Net`) is the only file that touches the SDK. Gameplay calls
  `Net.connect_to_server`, `Net.join`, `Net.send_move`, `Net.my_transform()` and `Net.visible_transforms()`. Upgrading
  or replacing the SDK changes one file.
- **Bindings:** generated into `spacetime_bindings/` by `templates/client/godot/tools/codegen.gd` from the server's schema. They are committed
  so the project opens without a server.
- **Scenes** render from the client cache. They never invent authoritative state. Input becomes intent reducers
  (`set_input(dir_x, dir_y, seq)`).

## SDK lessons

1. `client.db` is null until connected. Register table callbacks in the `connected` handler.
2. Unsubscribing does not evict cached rows, and overlapping subscriptions are not ref-counted. Use one subscription per
   AOI cell, subscribe new cells before dropping old ones, and filter reads by the current cell set.
3. `one_time_token = true` gives a fresh identity every run. Store a token per `--profile` under `user://`.
4. Tables need a primary key for updates and deletes to reach the cache.
5. After regenerating bindings, run `godot --headless --import` so `class_name`s register.
6. Headless test runs: give each client its own log file, never a shared pipe. On Windows, a full pipe stalled the
   second client in our smoke test.

## Movement feel

- Send input on change, not every frame, with a sequence number.
- Locally predict your own square and reconcile to the server transform with smoothing.
- Interpolate remote entities 100-150 ms behind.

## Test

```
python tools/kit.py smoke --godot      # two headless Godot clients see each other move
```

Set `GODOT` to the Godot 4.6.3 binary (console build on Windows).

## Gotchas

- The community SDK tracks SpacetimeDB versions with a lag. Check `stdb.lock [godot_sdk]` and test after every
  server bump.
- `--headless` still needs the `.godot/` import cache. Run `--import` once on a fresh clone.
- For a C# Godot project you can use the official C# client SDK instead (`skills/vendor/official/csharp-client`).
