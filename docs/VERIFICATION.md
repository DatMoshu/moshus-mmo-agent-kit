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

## 2026-10-30: Windows 11 x86_64 (workstation)

The environment was the SpacetimeDB 2.14.0 Windows release (CLI and standalone server running in an
isolated `--root-dir`), rustup 1.97.1 msvc with wasm32 installed, Node 22.15, Python 3.12, and Godot 4.6.3
(console build). This machine had **no Visual Studio C++ Build Tools**.

| Check | Command | Result |
|---|---|---|
| Toolchain doctor | `python tools/kit.py doctor` | spacetime, rust, wasm32, node, godot, python OK; **msvc FAIL** (no `link.exe`) |
| rust-single builds on Windows | `cargo build --target wasm32-unknown-unknown --release` | **UNVERIFIED**: build scripts need the MSVC linker. Install "Build Tools for Visual Studio" (C++ workload), or build on Linux/WSL |
| Publish a prebuilt module | `KIT_WASM=mmo_server.wasm python tools/kit.py publish` (`--bin-path`) | OK (wasm built on Linux) |
| TS bindings from the wasm | `spacetime generate --bin-path` | OK |
| Two-player smoke (TS SDK) | `python tools/kit.py smoke` | **PASS** (reducer p95 about 2.5 ms) |
| Two-player smoke (Godot 4.6.3) | `python tools/kit.py smoke --godot` | **PASS** on 2 of 2 runs after the fixes below |
| Godot bindings drift check | `python tools/kit.py bindings --check` | PASS (only line order differed) |
| Load gate, 50 bots x 20 s | `python tools/kit.py loadtest --bots 50 --duration 20` | **PASS**: p99 about 17 ms, avg tick lateness about 2.7 ms, level 0, about 850 row updates per bot per second |

Fixes made because of the Windows run:

* `kit.py` decodes child output as UTF-8. The Windows default code page crashed on CLI output.
* `kit.py` finds `cargo` in `~/.cargo/bin` when it is not on PATH. `doctor` checks for the MSVC linker.
* `KIT_WASM` lets `publish` and `bindings` use a prebuilt `.wasm` (`--bin-path`).
* The Godot smoke writes to log files instead of pipes. A full 4 KB Windows pipe stalled the second
  client until the first one exited, so the two clients were never online at the same time.
* The Godot autopilot paces back and forth. Clients stay near spawn and in each other's area of interest
  even when they start a few seconds apart.
* The GDScript codegen emits tables in an order that varies by server, so `bindings --check` ignores pure reordering.
