# Moshu's MMO Agent Kit

**An agent kit for building multiplayer games on [SpacetimeDB](https://spacetimedb.com).**
It gives you 18 specialist agent roles, 22 skills, rules and gates for an AI coding agent
(Claude Code, Codex, Cursor, Grok and others), plus a server template and client starters that
have been run end to end, a bot harness, and a load gate. Start with two players moving in 30
minutes, then grow the same design toward thousands of players.

> Pinned to **SpacetimeDB 2.14.0** (`stdb.lock`). SpacetimeDB moves fast, and most agent
> mistakes come from version drift, so everything here is locked and checked.

## What's inside

| Path | What it is |
|---|---|
| `AGENTS.md`, `CLAUDE.md` | Entry points your coding agent reads first: hard rules, routing, gates |
| `agents/` | 18 role definitions (architect, schema, reducer, sharding, netcode, client, security, load test, licence steward, ...) |
| `skills/` | 22 kit skills (patterns, gotchas, wrong-vs-right, checklists) plus the 11 official SpacetimeDB skills vendored in `skills/vendor/official/` |
| `rules/` | Non-negotiables and the hallucinated-API catalog used by `kit.py check` |
| `docs/` | Decision tree, scale ladder (10 to 5,000 players), processes, verification log, licensing guide (not legal advice) |
| `templates/server/rust-single` | A running Rust world module: admission, players, 20 Hz movement tick, AOI cells, health and degradation levels |
| `templates/client/godot` | A Godot 4.6 client on the MIT flametime SDK behind a small `Net` seam, with a headless autopilot test |
| `templates/server/ts-single` | The same world in TypeScript, wire-compatible with every client (verified) |
| `templates/server/rust-sharded` | Global and region databases with 2.14 cross-database outbox handoff, plus `dev_up.py` (verified locally) |
| `templates/sidecar` | A Node helper process: world census, health-guard pattern, and a place for NPC/outbox work (verified) |
| `templates/client/web-admin` | Vite + TypeScript live map and admin console (built and verified in headless Chrome) |
| `templates/client/unity` | Thin Unity starter. The session logic is verified headlessly with .NET; the editor was not run |
| `templates/client/unreal` | Thin Unreal C++ starter, with bindings generated and the API checked by hand. **Not compiled** |
| `tools/kit.py` | One CLI: `doctor`, `server`, `publish`, `bindings`, `smoke`, `loadtest`, `check`, `new`, `vendor-skills`, `kb-export` |
| `tools/loadtest/bots` | A TypeScript bot swarm (SDK 2.14): smoke test, AOI-aware swarm, latency percentiles, tick health |
| `evals/`, `recipes/`, `kb/` | Agent evals, task recipes, and the public knowledge base (JSON plus SQLite) |

## 30-minute quickstart: two players moving

You need **SpacetimeDB 2.14.0**, **Rust 1.97.1** with the `wasm32-unknown-unknown` target,
**Node 22+**, and **Python 3.11+**. Godot 4.6.3 is optional (for step 6).

**1. Install the toolchain (about 10 minutes, once).**

```bash
# SpacetimeDB CLI (macOS/Linux). On Windows: iwr https://windows.spacetimedb.com -useb | iex
curl -sSf https://install.spacetimedb.com | sh
spacetime version install 2.14.0 && spacetime version use 2.14.0

# Rust: https://rustup.rs, then:
rustup toolchain install 1.97.1 --target wasm32-unknown-unknown
```

**2. Check everything against `stdb.lock`.**

```bash
python tools/kit.py doctor          # every line should be OK (Godot is optional)
```

**3. Start a local SpacetimeDB.** Leave it running in its own terminal.

```bash
python tools/kit.py server          # = spacetime start --listen-addr 127.0.0.1:3000
# Add --isolated to keep the CLI config and data under .kit/, leaving your global config alone.
```

**4. Build and publish the world module.** The first build takes a few minutes.

```bash
python tools/kit.py publish         # builds templates/server/rust-single -> database "mmo-dev"
```

**5. Prove two players can join and see each other move.**

```bash
python tools/kit.py smoke
# ... "verdict": "PASS" ... SMOKE PASS
```

Two bot clients connect, join, move in different directions, and each one checks that it saw
the other move. This uses the real SDK, the real subscriptions, and the real tick.

**6. (Optional) Do the same with Godot.**

```bash
GODOT=/path/to/godot python tools/kit.py smoke --godot   # two headless Godot clients
```

To play by hand, open `templates/client/godot` in Godot 4.6.3 and run it twice
(Debug > Customize Run Instances > 2). Move with WASD or the arrow keys.

**7. Load it.**

```bash
python tools/kit.py loadtest --bots 100 --duration 20     # PASS / CONCERNS / FAIL vs tools/loadtest/budgets.json
```

**8. Make it yours.**

```bash
python tools/kit.py new my-game --dest ..    # copies server + client + tools + rules into ../my-game
python tools/kit.py new my-mmo --server ts-single --client web-admin --sidecar   # other combinations
```

Then point your agent at it: *"Read AGENTS.md. Add a chat channel per region, following
skills/stdb-schema-design and the reducer gates."*

## How the agent side works

* **`AGENTS.md`** is the contract. It covers the version pin, hard rules (identity, scheduled
  reducers, no I/O in reducers, private by default), and the definition of done (build, bindings,
  `check`, smoke, and a load gate for hot paths).
* **Roles** in `agents/` say what each specialist owns, what it reads, what it must never do,
  and how it hands off. A role has a model hint: deep-reasoning roles (architect, security,
  sharding) are marked `opus`, and the rest work on any capable model.
* **Skills** in `skills/` are short, concrete, and checked against the 2.14 API. Each skill
  has a "wrong vs right" section, because agents copy the first example they see.
* **`kit.py check`** greps for APIs that agents commonly invent or remember from older versions
  (for example `ctx.identity()` used as the database identity, `spacetime_module!`,
  `#[spacetimedb(table)]`, or `--project-path`) and prints the 2.14 fix.

## Scale in one paragraph

A SpacetimeDB database is one transactional actor, so a single world database is the right
choice up to a few hundred concurrent players doing movement plus gameplay. Past that, split
it into a **global** database (accounts, social, economy) and **region** databases (simulation),
linked with 2.14 inter-database calls (outbox tables). There is no cross-database transaction,
so moving a player or item between regions uses **lock -> offer -> accept -> delete ->
activate**. See `docs/scale-ladder.md` and `skills/stdb-sharding-plan`.

## Licensing (read this before you ship)

This kit is Apache-2.0. The SpacetimeDB **server** is BSL 1.1: you may run it in production,
but not offer it to others as a database service. On 2031-10-25 it converts to AGPLv3 with a
linking exception. The vendored Godot SDK is MIT. See `NOTICE` and
`docs/legal/LICENSING.md` (**not legal advice**). Do not paste licensed game content or GPL
code into a kit-based repo. The `license-steward` role exists to catch that.

## Status

Every template states whether it has been verified, and `docs/VERIFICATION.md` records what
was run, on which OS, and what the result was. Anything not marked verified is a starter you
should expect to fix.

## Contributing

Issues and PRs are welcome. Run `python tools/kit.py check` and the smoke test before opening
a PR. When you bump SpacetimeDB, change `stdb.lock` first, then follow
`docs/processes/version-bump.md`.
