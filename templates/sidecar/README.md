# sidecar: a helper process with its own identity

**Status: VERIFIED (watch + /health + guard denial + guard success)** on Linux against `rust-single`-compatible
modules (2.14.0, Node 24). The success path (closing admission as an authorised operator) was verified with the
operator role from `recipes/operator-role.md`. The starter modules alone accept only the publisher as admin.

Some work does not belong inside a reducer: anything that talks to the outside world (HTTP, email,
payments, LLMs), long waits, or supervision. Run it in a **sidecar**, a normal SpacetimeDB
client that runs on a server next to the database and has its own identity.

This template is a small ops watcher:

* subscribes to `tick_health`, `world_config` and `player`
* prints a status line every `--every` seconds
* serves `GET /health` on `127.0.0.1:<--http-port>` (200 when connected, tick fresh and not red; 503 otherwise)
* `--guard`: if `tick_health.level >= --red-level` for `--red-ticks` checks in a row, calls
  `set_admission_open(false)` so no new players pile onto an overloaded world
* exits with code 2 on disconnect, so a supervisor (systemd, pm2, Docker `restart: always`) restarts it

```bash
npm install
python ../../tools/kit.py bindings          # or: spacetime generate --lang typescript --out-dir src/module_bindings --module-path ../server/rust-single
npx tsx src/main.ts --uri ws://127.0.0.1:3000 --db mmo-dev --once          # one status line, exit 0 = PASS
npx tsx src/main.ts --uri ws://127.0.0.1:3000 --db mmo-dev --http-port 8787 --guard
```

| Flag | Default | Meaning |
|---|---|---|
| `--uri` / `--db` | `ws://127.0.0.1:3000` / `mmo-dev` | Where to connect |
| `--every` | 5 | Seconds between status lines and guard checks |
| `--http-port` | 0 (off) | Local health endpoint. Binds 127.0.0.1 only; put a reverse proxy in front if you expose it |
| `--guard` | off | Enable the admission guard |
| `--red-level` / `--red-ticks` | 3 / 3 | What counts as red, and for how many checks in a row |
| `--token-file` | none | Persist the sidecar's identity token so it keeps the same identity across restarts |
| `--once` | off | Print one line and exit (CI smoke) |

## Identity and tokens

Without `--token-file` the sidecar gets a fresh anonymous identity every run. That is fine for
watching. For acting, give it a stable identity with `--token-file <path outside the repo>`. The
file is a credential: keep it out of git (`.sidecar/` is ignored), chmod 600, and never paste it
into chat, logs or an AI prompt.

## Giving the sidecar a role

The starter modules have one admin, the identity that published the database. To let a sidecar act
(the drop-in code is `recipes/snippets/operator.rs`):

1. Add an `operator` table (`identity` primary key, `role` string) and a `require_operator(ctx)` helper
   that accepts the admin **or** a row in `operator`.
2. Add an admin-only `grant_operator(identity, role)` reducer.
3. Start the sidecar once with `--token-file`, copy the identity it prints, and call
   `spacetime call <db> grant_operator 0x<identity> '"ops"'`.
4. Use `require_operator` in the reducers the sidecar may call (`set_admission_open` here).

Never let the sidecar use the publisher's CLI token. Separate identities keep the audit trail clear
and let you revoke the sidecar without locking yourself out.

## Patterns that grow from this

* **Outbound effects (email, webhooks, payments):** the module writes a row into an `outbox`-style
  table. The sidecar subscribes, performs the effect, and calls an `ack_*` reducer with the result.
  Make the effect idempotent on the row id, because the sidecar can crash between doing the effect
  and sending the ack.
* **NPC brains / LLM calls:** the sidecar reads world state, decides, and calls the same reducers a
  player would (`set_input`). The module stays deterministic and validates every call.
* **Cross-database calls:** in 2.14, prefer the in-module IDC outbox (`templates/server/rust-sharded`)
  over a sidecar relay when both ends are SpacetimeDB databases. It is exactly-once and in order.
