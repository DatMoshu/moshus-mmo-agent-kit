# Decision tree: what should I build?

Answer the questions in order. Each answer points at a template, skill or doc. Write the answers into a one-page
ADR (`docs/adr/`) before writing code; the `stdb-architect` agent does this with you.

## 1. How many players at the same time, in the same world?

| Peak concurrent players | Topology | Start from |
|---|---|---|
| up to ~200 | one module, one database | `templates/server/rust-single` (or `ts-single`) |
| ~200-500 | one module, tuned (AOI, quantized hot rows, write-on-change) | same, plus `skills/stdb-aoi-subscriptions`, `skills/stdb-load-test` |
| ~500-2,000 | one global database + a few region databases (sharding by space) | `templates/server/rust-sharded`, `skills/stdb-sharding-plan` |
| 2,000+ | many regions, global services split by function | `docs/scale-ladder.md` rungs 1,000 and 5,000 |

These are **planning estimates**, not guarantees. Every SpacetimeDB database is a single-threaded actor, so the real
limit is how much reducer work and subscription fan-out your game generates per tick. Measure with
`python tools/kit.py loadtest`. Do not shard until a load test says you must (ADR KIT-001).

## 2. Which server language?

- **Rust** (the default, ADR KIT-002): the reference templates, the best-tested path, the strongest type checks.
- **TypeScript**: when your team is web-first and the game is small or medium. Same rules apply
  (`rules/typescript-module.md`).
- **C#**: supported by SpacetimeDB, not templated here. Use the official `csharp-server` skill in
  `skills/vendor/official/`.

## 3. Which client?

| You want | Use | Notes |
|---|---|---|
| A 2D/3D game fast, open source engine | Godot 4 (`templates/client/godot`) | community GDScript SDK, vendored and pinned |
| Mobile/console reach, big asset store | Unity (`templates/client/unity`) | official C# SDK |
| AAA rendering | Unreal (`templates/client/unreal`) | official C++ SDK (`--lang unrealcpp`) |
| Browser game or tools | web (`templates/client/web-admin`) | official TS SDK (`spacetimedb`, `spacetimedb/react`) |
| Headless bots, tests | `tools/loadtest/bots` | the same TS SDK |

You can have several clients on one module. Bindings are generated per client (`skills/stdb-bindings-regen`).

## 4. Does the game need the outside world?

| Need | Use |
|---|---|
| Short HTTP call (webhook, verify a receipt) | a `#[procedure]` with `ctx.http`, then `ctx.with_tx` |
| Long work, secrets, AI/LLM calls, payments, Discord bots, email | a sidecar service (`templates/sidecar`, `skills/stdb-sidecar`) |
| Analytics or exports | a sidecar subscribed to the tables, writing elsewhere |

Reducers can never do I/O. They must stay deterministic.

## 5. How do players log in?

- **Anonymous identities with saved tokens** (the template default): fine for prototypes and playtests.
- **OIDC** (SpacetimeAuth or your own provider, RS256/ES256): for anything with accounts. HS256 is rejected since
  2.12. See `skills/stdb-auth-identity`.
- **Admission control** (allow-list, invites, bans): enforced in `client_connected` and every player reducer.

## 6. Where will it run?

| Option | When | Watch out for |
|---|---|---|
| Local `spacetime start` | development | nothing; this is free |
| Maincloud (Clockwork Labs hosted) | you don't want to run servers | pricing and quotas; `skills/stdb-deploy-maincloud` |
| Self-hosted standalone | full control, one production instance | BSL terms (`docs/legal/LICENSING.md`), backups, TLS; `skills/stdb-deploy-selfhost` |
| Several self-hosted instances | sharded worlds across machines | needs a commercial license under the BSL, and IDC only works within one server; see `docs/scale-ladder.md` |

## 7. What is the riskiest assumption?

Name it, then prove it first with the smallest possible spike, a load test, or a playtest. Typical candidates are tick
cost at peak, AOI fan-out in crowds, cross-region handoff, and auth integration.
