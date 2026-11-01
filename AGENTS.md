# AGENTS.md: contract for AI agents working in a SpacetimeDB MMO

You are working in a repo built from **Moshu's MMO Agent Kit**. Read this file first, every
session. It is short on purpose. Details live in `skills/`, `rules/` and `docs/`.

## 0. Versions are locked

* `stdb.lock` is the truth. **SpacetimeDB 2.14.0**: the CLI, the `spacetimedb` crate (`=2.14.0`),
  and the `spacetimedb` npm SDK all move together. Rust is 1.97.1 (`rust-toolchain.toml`).
* Do not "upgrade to latest" or add a dependency without updating `stdb.lock` and following
  `docs/processes/version-bump.md`.
* If your memory of an API disagrees with the vendored official skills
  (`skills/vendor/official/`) or with the template code, **the repo wins**. Your memory is
  probably of 1.x or of a pre-release API.

## 1. Hard rules (break one and the work is rejected)

1. **Server-authoritative.** Clients send *intent* (inputs, requests). Reducers validate and
   decide. Never trust client positions, damage, prices, or timestamps.
2. **Authenticate with `ctx.sender()`.** Never take an identity as a reducer argument. The
   module's own identity is `ctx.database_identity()`. In 2.14, `ctx.identity()` is deprecated,
   so don't use it.
3. **Guard scheduled reducers.** They are callable by clients unless you check
   `ctx.sender() == ctx.database_identity()`.
4. **Reducers are deterministic transactions.** No network, file I/O, wall clock, threads,
   or `rand`. Use `ctx.timestamp`, `ctx.random()`, and procedures or sidecars for I/O.
   A returned `Err` rolls back everything.
5. **Private by default.** Only mark a table `public` if every row is fine for every client to
   read. Hidden information goes in private tables plus views or a narrow public projection.
6. **Index every filter.** Every `filter`/`find` path and every subscription `WHERE` column
   has an index. Never scan a hot table inside the tick.
7. **Hot and cold rows are separate.** Fast-changing state (transform) goes in narrow tables.
   Names, stats, and cosmetics go in cold tables. Write only on change, and quantize.
8. **Bounded work per tick.** Every loop over players or entities has a budget. Shed optional
   work when `tick_health.level >= 2`.
9. **No cross-database transactions.** Cross-region moves use lock -> offer -> accept ->
   delete -> activate with idempotent message ids (`skills/stdb-sharding-plan`).
10. **No secrets in the repo.** Tokens, keys, `.env`, and server addresses stay out of git.
11. **No licensed game content and no GPL code** in this repo. Describe them; don't paste them
    (`agents/license-steward.md`).

## 2. Definition of done (every module change)

```
python tools/kit.py check            # hallucinated-API / anti-pattern scan: 0 findings
cargo build --target wasm32-unknown-unknown --release   # in the module dir
python tools/kit.py publish          # local dev server
python tools/kit.py bindings         # regenerate every client's bindings; commit them
python tools/kit.py smoke            # two identities join + see each other move: PASS
python tools/kit.py loadtest         # only if you touched the tick, AOI, or a hot table: not FAIL
```

If you cannot run a step, say so explicitly in your report. Never claim a step passed when
you did not run it.

## 3. Routing: which role, which skill

| Task | Role (`agents/`) | Skill (`skills/`) |
|---|---|---|
| New game / topology / "can this scale?" | stdb-architect | stdb-new-game, stdb-sharding-plan |
| Tables, indexes, visibility | stdb-architect, module-engineer | stdb-schema-design |
| Reducers, scheduled jobs | module-engineer | stdb-reducer-author, stdb-tick-loop |
| Interest management, bandwidth | netcode-engineer | stdb-aoi-subscriptions |
| Godot / Unity / Unreal / web client | client-engineer-* | stdb-godot-client, stdb-unity-client, stdb-unreal-client, stdb-web-client |
| Login, accounts, admission | security-auditor | stdb-auth-identity |
| Changing a live schema | data-migration-specialist | stdb-migration |
| New SpacetimeDB release | stdb-docs-librarian, live-ops-engineer | stdb-upgrade-runtime |
| Bots, budgets, capacity | load-test-engineer | stdb-load-test, stdb-observability |
| Scripted ops runs that flake or fail halfway | live-ops-engineer | stdb-ops-runners |
| Global + regions, handoffs | sharding-specialist | stdb-sharding-plan |
| Heavy AI / pathfinding / mapgen | module-engineer, procgen-engineer | stdb-sidecar |
| Before any external playtest | security-auditor, qa-playtest-lead | stdb-security-review |
| Deploy | live-ops-engineer | stdb-deploy-selfhost, stdb-deploy-maincloud |
| Copying third-party code/data, launching | license-steward | stdb-license-check |
| Milestones, acceptance | producer | (docs/processes/) |

## 4. Where things are

* `templates/server/rust-single/src/lib.rs` is the reference module. Copy its shapes before you
  invent new ones.
* `rules/` holds the non-negotiables (`rules/*.md`) and the wrong API catalog
  (`rules/hallucinations.json`).
* `docs/decision-tree.md` covers the language, client, hosting and topology choices.
  `docs/scale-ladder.md` covers what changes at 10, 50, 200, 500, 1,000 and 5,000 players.
* `skills/vendor/official/` holds Clockwork Labs' own skills (Apache-2.0, unmodified). Use them
  for API reference.

## 5. Reporting

End every task with: what changed (files), what you ran and the result, what you did not run
and why, and any risk you noticed (authority, cost per tick, migration, licence).
