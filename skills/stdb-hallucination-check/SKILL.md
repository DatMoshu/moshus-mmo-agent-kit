---
name: stdb-hallucination-check
description: Catch invented or outdated SpacetimeDB APIs (1.x syntax, wrong attributes, impure calls) in code and docs before they ship. Use after any AI-written module or client code, and in CI.
---

# Hallucination check

## Run

```
python tools/kit.py check
```

This scans `.rs`, `.ts`, `.cs`, `.gd` and `.md` files with `rules/hallucinations.json`. Each rule has an id, a regex,
file extensions, a message and a fix. The command exits non-zero on errors.

## The usual suspects (2.14)

| Wrong | Right |
|---|---|
| `#[spacetimedb(table)]`, `#[spacetimedb(reducer)]` | `#[spacetimedb::table(accessor = x)]`, `#[spacetimedb::reducer]` |
| `#[table(name = player)]` used as the accessor | `accessor = player` (`name` sets the SQL name only) |
| `ctx.identity()` | `ctx.database_identity()` |
| `#[table(..., schedule(tick))]` | `scheduled(tick)` |
| `rand::thread_rng()`, `std::time::SystemTime::now()` | `ctx.rng()`, `ctx.timestamp` |
| `Player::filter_by_name(&n)` | `ctx.db.player().name().find(&n)` |
| `spacetimedb-sdk` crate in a module | `spacetimedb` crate (the SDK is for clients) |
| `#[derive(SpacetimeType)]` on a table | table attribute only |
| `ctx.sender` (field) | `ctx.sender()` (method, 2.x) |
| `spacetime publish --project-path` | `--module-path` (or `--bin-path`) |
| HS256 JWT secrets | RS256/ES256 OIDC issuer |

## When unsure

1. Search `skills/vendor/official/*/SKILL.md`, the official skills at the pinned version.
2. Check the crate docs for the pinned version on docs.rs.
3. Build it: `cargo build --target wasm32-unknown-unknown --release`. The compiler is the final authority.
4. If you found a new pattern, add a rule to `rules/hallucinations.json` with a test sample in `evals/`.
