# Release-preparation validation scope

The minimal gate is [tools/quickstart/verify.py](../../tools/quickstart/verify.py).
Run it in a disposable clone with pinned prerequisites. Receipts/logs remain
external; sanitize local paths and credentials before publishing evidence.

## Measured preparation runs, 2026-11-10

| Host and revision | Actual result | Timing and limit |
|---|---|---|
| Windows 11, `45265be` | Source-built rust-single Wasm, locked npm install, fresh bot bindings/typecheck, isolated publish, two-client smoke, 10-bot/5-second load: PASS | 54.062 seconds including cold dependency downloads/build; prerequisites excluded |
| Dell PC, Debian 13 x86_64, `59e7d13` | Source build, fresh bot bindings/typecheck, isolated publish and two-client smoke: PASS | 68.579 seconds including the separate failed load diagnostic below; cold build 47.853 seconds |
| Same Dell run, optional 10-bot/5-second load | **FAIL**: p95 393.5 ms, p99 522.8 ms against 150/400 ms failure limits | All 10 bots joined, zero reducer errors, tick-health level 0; this does not override latency failure |

The Dell began without Git, Rust, Node, SpacetimeDB or a C compiler. Isolated
user-local prerequisites took 41.43 seconds to download/extract/install, measured
separately. Rust 1.97.1 and STDB 2.14.0 remained pinned; Node was 22.18.0. Zig
0.14.1 supplied the host C linker because the machine had no system compiler or
passwordless sudo. This was a test-host accommodation, not a new kit dependency.
The runner used new Cargo/npm/build directories and a local Git-bundle clone;
no cached Wasm, generated bindings, fleet server or private package registry was
needed. The Debian kernel was 6.12.113, Python 3.13.5, with two logical CPUs.

These are measured runs at the named commits, not universal setup-time or capacity
claims. The retained release report binds the final candidate to its own fresh
clone result. Keep the earlier failed latency result even if another run passes.

## Issues found by fresh runs

Windows needs the Visual Studio C++ workload and developer environment. The
ordinary-shell attempt exposed Git link.exe shadowing the Microsoft linker;
the runner now identifies it. npm also required inherited PATH normalization.
The CLI now installs locked packages and uses installed tsx rather than allowing
npx to download a tool implicitly. Smoke and load gates reject failed process
exits even if partial JSON looks successful.

The [Linux CI workflow](../../.github/workflows/verify.yml) is authored but has not
run on hosted GitHub Actions. Its exact environment-export snippet was executed
locally and checked for two newline-delimited pinned variables. Historical
engine/platform results remain in [VERIFICATION.md](../VERIFICATION.md). macOS,
Unity editor, Unreal compilation and current multi-database handoff are not part
of this fresh minimal-path proof.

## Review and repeat

See [testing](../wiki/Testing.md), [release maintenance](../wiki/Release-maintenance.md)
and [dependency inventory](../legal/DEPENDENCIES.md). Re-run at the release SHA,
retain commands, receipt, logs, versions and clean-checkout status, and state all
skipped checks. A successful source build does not establish client correctness,
production scale or licensing compliance.
