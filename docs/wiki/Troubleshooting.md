# Troubleshooting

Start with doctor, the failing command's `--help`, and its output. Confirm pins, executable paths, schema family, URL and database. Do not mask failures with retries or wipes.

| Symptom | Check and action |
|---|---|
| CLI/SDK mismatch | Compare versions/manifests with stdb.lock; restore coordinated pins |
| Windows linker missing | Install Visual Studio C++ workload; record Linux/WSL separately if used |
| Wasm target missing | Install wasm32-unknown-unknown for Rust 1.97.1 |
| Server ping fails | Inspect owned server logs/port; use the same URL everywhere |
| Publish denied | Verify CLI config/root and publisher identity; do not blindly rotate credentials |
| Join denied | Review admission flag and authorized admin/allowlist |
| Godot plugin class missing | Import fresh project before codegen; kit bindings handles the initial cache |
| Smoke fails after connection | Confirm schema, bindings, join, own-transform subscription and tick health |
| Reconnect cannot move | Check same-token join resets input sequence; add an assertion |
| Offline ghost persists | Check transform deletion and client row-delete callbacks |
| Bindings differ | Generate from intended module/schema and review the diff |
| Load concerns/failure | Inspect readiness, row volume, lateness and budgets; quantify bottlenecks |

KIT_RETRIES and KIT_RETRY_BASE configure transient-transport retries with backoff. A real negative test verdict is not transient. See [ops runners](../processes/ops-runners.md) for reentry and BOM-tolerant JSON handling.

KIT_WASM selects prebuilt Wasm: record its source revision/builder and do not call that a local source build. GODOT selects an engine executable; SPACETIME selects the CLI; SPACETIME_ARGS supplies global CLI options. Environment syntax differs between PowerShell and POSIX shells.

Reports need sanitized reproductions, revision, OS/tool versions, template, command and verdict. Exclude tokens, private endpoints, .env and personal data. Report exploitable details through [SECURITY.md](../../SECURITY.md).
