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
| Godot bindings | `templates/client/godot/tools/codegen.gd` headless from `/v1/database/<db>/schema?version=10` | 22 files generated |
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

## 2026-10-31: Linux x86_64 (kit authoring box), `templates/server/rust-sharded`

The environment was the same as the 2026-10-30 Linux entry (SpacetimeDB 2.14.0 standalone, Rust 1.97.1).

| Check | Command | Result |
|---|---|---|
| Workspace builds (global + region) | `cargo build --target wasm32-unknown-unknown --release` | OK, 0 warnings |
| IDC bindings from `spacetime.json` | `spacetime generate mmo-region-1 -y` (two passes, see README) | OK: `region/src/remote_bindings/{global,region}` |
| Publish + wire 2 regions by hand | README runbook | OK |
| Publish + wire 3 regions, then `--wipe` | `python scripts/dev_up.py --regions 3` | OK; neighbours peered, global registry correct |
| Handoff region 1 -> 2 | `gm_teleport` over the border | **PASS**: player deleted in 1, `departure.to_region = 2`, Active in 2 at the target position, global `player_home.region_id = 2`, all outboxes empty |
| Handoff region 2 -> 1 | same, reverse | **PASS** |
| Spoofed IDC calls from a client | `spacetime call ... accept_handoff`, `... player_entered` | **PASS**: rejected (`caller is not a peer region`, `caller is not a registered region`) |
| Heartbeats | `SELECT * FROM region` in global | OK, `last_heartbeat` advances every 5 s |

Lessons recorded from these runs:

* `spacetime call` disconnects after every call, and the template clears input on disconnect, so CLI
  movement tests stall. The admin `gm_teleport` reducer exists for operators and smoke tests.
* Pass `--` before reducer arguments, or negative numbers are read as flags.
* Inside a folder with a multi-database `spacetime.json`, `spacetime call` needs `--no-config` (or a
  database from the config).

Not verified: rust-sharded on Windows. (A client following `my_departure` across regions was verified later; see the region-hop entry below.)
(same MSVC limit as rust-single), and load across regions.

## 2026-10-31: Linux x86_64 (kit authoring box), `templates/server/ts-single`

| Check | Command | Result |
|---|---|---|
| Typecheck | `npm install && npx tsc --noEmit` | OK, 0 errors |
| Publish (TS bundled by the CLI) | `spacetime publish --module-path templates/server/ts-single` | OK; tick running at level 0 |
| Two-player smoke, TS SDK (bindings generated from **rust-single**) | `python tools/kit.py smoke --db <ts db>` | **PASS** (reducer p95 about 11 ms) |
| Two-player smoke, Godot 4.6.3 | `python tools/kit.py smoke --godot --db <ts db>` | **PASS** |
| Load gate, 50 bots x 10 s | `python tools/kit.py loadtest --bots 50 --duration 10 --db <ts db>` | **PASS**: level 0, avg lateness about 0.2 ms, about 830 row updates per bot per second |

The smoke runs used bindings generated from the Rust module, which confirms the two modules are
wire-compatible.

## 2026-10-31: Linux x86_64, `templates/sidecar`

| Check | Command | Result |
|---|---|---|
| Typecheck | `npx tsc --noEmit` | OK |
| One-shot status | `npx tsx src/main.ts --db <db> --once` | **SIDECAR PASS** (read tick_health, world_config, player) |
| Health endpoint | `--http-port 18777`, `curl /health` | 200 with JSON status |
| Guard denial | `--guard --red-level 0 --red-ticks 1` with a non-admin identity | `set_admission_open` rejected with `admin only`, recorded in `last_error`; process keeps running |
| Guard success path | sidecar holding an operator role | **PASS** with `recipes/snippets/operator.rs` (see the recipe snippets entry below) |

Lesson: `table.count()` returns a `bigint` in the TS SDK. Convert with `Number()` before `JSON.stringify`.

## 2026-10-31: Linux x86_64, `templates/client/web-admin`

| Check | Command | Result |
|---|---|---|
| Bindings | `python tools/kit.py bindings` | written to `src/module_bindings` |
| Build | `npm run build` (tsc + Vite 8.3.5) | OK, 121 kB JS (32 kB gzip) |
| Runtime | `vite preview` + headless Chrome (read through DevTools protocol) against a live TS-module database | Subscribed; cards showed level 0, tick count, lateness, admission open, role `viewer`; 56 player rows; admin controls hidden for a non-admin identity |
| Admin actions from the browser | as the publisher identity | **not verified** (would need the publisher's token in the browser) |

Lesson: `chrome --dump-dom` never returns while a page holds an open WebSocket. Use the DevTools
protocol (`--remote-debugging-port`, `Runtime.evaluate`) to read a live SpacetimeDB page headlessly.

## 2026-10-31: Linux x86_64, `templates/client/unity` and `templates/client/unreal`

| Check | Command | Result |
|---|---|---|
| Unity: C# bindings | `spacetime generate --lang csharp` from rust-single | OK |
| Unity: session logic compiles | `ci/SessionCheck`: .NET 8 + `SpacetimeDB.ClientSDK` 2.14.0 compiling `MmoSession.cs` + bindings | OK, 0 warnings |
| Unity: two-client smoke | `dotnet run -- <url> <db>` against the Rust **and** the TS starter modules | **SESSION PASS** on both |
| Unity: editor / `MmoWorldView.cs` | Unity 2022.3+ | **not verified** (no Unity on the box) |
| Unreal: bindings | `spacetime generate --lang unrealcpp --unreal-module-name MmoKitClient` | OK (generated headers + module files) |
| Unreal: API cross-check | `MmoGameManager` symbols matched against generated headers and SDK headers at `v2.14.0` | OK (manual) |
| Unreal: compile / play | UE 5.x | **not verified** (no Unreal Engine on the box) |

Lesson: put a Unity client's SpacetimeDB logic in a class with no `UnityEngine` types. It can then be
compiled and smoke-tested headlessly with plain .NET in CI, while the MonoBehaviour stays a thin view.

## 2026-10-31: `kit.py new` end-to-end

`kit.py new <name> --server {rust-single|ts-single|rust-sharded} --client {godot|web-admin|unity|unreal} --sidecar`
produced complete trees for all four combinations tried. For `--server ts-single --client web-admin --sidecar`:
`npm install`, then `kit.py publish` → `kit.py bindings` → `kit.py smoke` gave **SMOKE PASS**, and `npm run build` of the client passed.
Fixed during this check: `bindings` no longer fails when the project has no Godot client.

## 2026-10-31: sharded region-hop client (local 2.14)

* `templates/server/rust-sharded/client-example`: `tsc --noEmit` reported no errors. Ran `npx tsx src/hop.ts --global <global-db> --hops 2` against one global and three region databases, with output **HOP PASS**: two cross-database handoffs, the client reconnected with the same token each time, and the identity stayed the same.

## 2026-10-31: recipe snippets (local 2.14)

Each snippet in `recipes/snippets/*.rs` was appended to a scratch copy of `rust-single`, built for wasm32, and published to a scratch database.

| Snippet | Result |
|---|---|
| `inventory.rs` | Compiled. A max stack of 20 with a grant of 45, then a grant of 5, gave stacks 20/20/10. `give_item` out of range was rejected with "too far". **Not run:** a successful give between two players. |
| `idempotent.rs` | Compiled. Calling `grant_purchase` twice with the same request id applied once. |
| `chat.rs` | Compiled. With two SDK clients, the second client received the first's message, and a second `say` within 0.5 s was rejected with "slow down". |
| `operator.rs` | Compiled. With `set_admission_open` switched to `require_operator`, the sidecar (its own token, not the publisher's) ran `--guard --red-level 0 --red-ticks 1`. Before `grant_operator` it got "operator only"; after it, "admission closed", and `admission_open` became false. This also verifies the sidecar guard success path. |
