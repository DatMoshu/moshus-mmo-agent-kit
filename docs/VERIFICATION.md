# Verification log

This log records what was actually run, where, and with what result. Anything not listed here
is **unverified**. Re-run these checks after every version bump and add a dated entry.

## 2026-10-30: Linux x86_64 (kit authoring box)

The environment was the SpacetimeDB 2.14.0 standalone server and CLI (release build), Rust
1.97.1 with wasm32-unknown-unknown, Node 24, Python 3.13, and Godot 4.6.3 (headless).

| Check | Command | Result |
|---|---|---|
| Toolchain doctor | `python tools/kit.py doctor` | all OK |
| rust-single builds | `cargo build --target wasm32-unknown-unknown --release` | OK, 0 warnings |
| Publish (fresh, then schema change with `--wipe`, then hot update) | `python tools/kit.py publish` | OK |
| TS bindings | `spacetime generate --lang typescript` | OK; bot harness typechecks (`tsc --noEmit`) |
| Godot bindings | `tools/codegen.gd` headless from `/v1/database/<db>/schema?version=10` | 22 files generated |
| Two-player smoke (TS SDK 2.14) | `python tools/kit.py smoke` | **PASS** (A moved +x and B saw it; B moved -y and A saw it; reducer p95 about 3 ms) |
| Two-player smoke (Godot 4.6.3 + flametime SDK) | `python tools/kit.py smoke --godot` | **PASS** (both headless clients saw the other move) |
| Load gate, 100 bots x 10 s at 20 Hz | `python tools/kit.py loadtest --bots 100 --duration 10` | **PASS**: 100/100 ready, 0 errors, p95 about 33 ms, p99 about 63 ms, avg tick lateness about 0.1 ms, level 0, about 1,700 row updates per bot per second |

Lessons recorded from these runs, now in skills and docs:

* With 100 movers in a 3x3-cell AOI at 20 Hz, each client received about 1,700 row updates
  per second. Quantize positions, write only on change, and size cells to the view radius
  before going wider (`skills/stdb-aoi-subscriptions`).
* The bot first needs a subscription to its *own* transform before it knows which AOI cells
  to subscribe to.
* Offline players kept their transform rows, and clients rendered them as ghosts. The template
  now deletes the transform on disconnect and restores it on join.

## Windows x86_64

See the entries below. They were added when the kit was installed on a Windows workstation.
