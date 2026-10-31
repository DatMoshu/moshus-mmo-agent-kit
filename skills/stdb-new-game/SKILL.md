---
name: stdb-new-game
description: Scaffold a new SpacetimeDB 2.14 MMO from the kit (server module, chosen client, pinned versions, smoke test). Use when starting a project or a fresh prototype.
---

# New game from the kit

## When

You're starting a new game, or a throwaway prototype that should still be built the right way.

## Steps

1. **Check tools.** Run `python tools/kit.py doctor`. Fix every FAIL. On Windows without the C++ Build Tools, either install
   them or build the module on Linux/WSL and set `KIT_WASM` (see `docs/VERIFICATION.md`).
2. **Pick the client.** Use `docs/decision-tree.md`. The defaults are Godot for a 2D or 3D indie game, web for tools and
   browser games, and Unity or Unreal if the team already ships with them.
3. **Scaffold.**
   ```
   python tools/kit.py new my-game --dest ../my-game --server rust-single --client godot
   ```
   This copies the module into `server/` and the client into `client/`. It also copies `tools/`, `rules/`, `skills/`,
   `agents/`, `docs/`, `AGENTS.md` and `stdb.lock`, renames the crate and sets the dev database to `my-game-dev`.
4. **Own it.** Run `git init` in the new folder. Check `stdb.lock` and `server/Cargo.toml`, then commit.
5. **Run locally.**
   ```
   python tools/kit.py server        # terminal 1 (or --isolated for a throwaway data dir)
   python tools/kit.py publish
   python tools/kit.py bindings
   python tools/kit.py smoke         # two identities join and see each other move
   ```
6. **Write the north star.** Put one sentence in `docs/north-star.md` covering what the player does, how many play
   together, and what is persistent. The `producer` agent uses it.
7. **First ADR.** Record the topology choice: single module unless you can name why not (ADR KIT-001).

## Gates

- `doctor` is all OK, or every missing tool is written down.
- `smoke` PASSes on a fresh clone.
- `stdb.lock` matches the crate and SDK versions in `Cargo.toml` and `package.json`.

## Gotchas

- Version skew between the CLI, the crate and the SDK causes confusing codegen and deserialization errors. Everything
  comes from `stdb.lock`.
- `init` only runs on the first publish. Put seed data in an idempotent `ensure_*` reducer, as the template does with
  `ensure_world`.
- Never commit tokens, `.env` files or server addresses. The template `.gitignore` already excludes them.

## Hand off

Give the table map to `stdb-architect` and `module-engineer`. Give the client to the matching `client-engineer-*`.
