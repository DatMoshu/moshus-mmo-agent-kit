# Installation

The minimal path uses the Rust movement world and TypeScript bots. It needs no Godot editor, cloud account, private fleet service, or game assets. Initial tool/package downloads require network access. Work from a clone and run commands at its root.

| Tool | Pin or minimum | Why |
|---|---|---|
| Python | 3.11+ | CLI uses standard-library tomllib |
| Node.js | 22+ with npm | SDK bot harness and optional web/sidecar tools |
| SpacetimeDB | 2.14.0 | CLI, server, module and client protocol alignment |
| Rust | 1.97.1 | Module and host build scripts |
| Rust target | wasm32-unknown-unknown | Server module output |
| Godot | 4.7, optional | Godot client, import, binding generation and engine smoke |

[stdb.lock](../../stdb.lock) is the source of truth. Use the [official SpacetimeDB installation guidance](https://github.com/clockworklabs/SpacetimeDB#installing-spacetimedb) and [rustup](https://rustup.rs/); review downloaded installation commands before running them.

```sh
spacetime version install 2.14.0
spacetime version use 2.14.0
rustup toolchain install 1.97.1 --target wasm32-unknown-unknown
python tools/kit.py doctor
```

Doctor checks optional engine availability too; inspect individual results to distinguish an optional client from a blocker. Windows MSVC Rust builds need Visual Studio Build Tools with the C++ workload. Missing `link.exe` can break host build scripts even when output is Wasm. WSL/Linux is another build environment; record it as such.

## Isolated verification

```sh
python tools/quickstart/verify.py
```

This path builds rust-single from source with isolated Cargo/build state, installs locked npm dependencies, generates fresh TypeScript bot bindings, typechecks, starts an owned local server, publishes, and proves both clients observe movement. Godot is not required. The runner selects a free loopback port and prints its external evidence directory. It retains step logs and receipt.json and stops the owned server on exit. Review the receipt's final verdict and each step.

Use `--work-dir` with a **new** directory to choose evidence/state location, `--port` for an unused nondefault port, and `--loadtest` for a 10-bot/five-second diagnostic. The runner rejects port 3000 to avoid a typical development server. Its dependency/build state is isolated, but it installs bot node_modules and generates bot bindings inside the checkout; use a disposable clone for clean-checkout proof. Keep logs local and sanitize before sharing.

On Windows run from Developer PowerShell with the C++ workload; Git's link.exe can shadow the Microsoft linker in an ordinary shell. See [current release-preparation evidence](../public-readiness/README.md). Toolchain installation is a prerequisite and is excluded from measured runner time.

## Manual development loop

Terminal one:

```sh
python tools/kit.py server --isolated
```

Terminal two:

```sh
python tools/kit.py publish
python tools/kit.py smoke
```

The endpoint and database default to `[dev]` in stdb.lock. `--isolated` keeps server config/data under ignored `.kit`. All processes must target the same endpoint; inspect `--help` when changing ports. A port conflict is not a reason to stop another developer's server.

Use `SPACETIME` for a non-PATH executable and `SPACETIME_ARGS` for global CLI config/root options. Configure the shell's environment variables rather than building shell command strings. See [troubleshooting](Troubleshooting.md).

## Platform evidence

[VERIFICATION.md](../VERIFICATION.md) records historical Linux builds/runtime checks. Historical Windows runtime tests used Linux-built Wasm because the host lacked the C++ linker; they do not prove Windows source builds. That ledger records no macOS runtime proof. Current candidate evidence must state its actual OS, commands, versions, and duration separately. Download time, caches, and hardware make a universal setup-time promise inappropriate.

Next: [first project](First-project.md) or [testing](Testing.md).
