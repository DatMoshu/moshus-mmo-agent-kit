# Vendored official SpacetimeDB skills

These 11 folders are **unmodified copies** of the agent skills published by Clockwork Labs in the SpacetimeDB repository
(`codex-plugin/plugins/spacetimedb/skills`). They are licensed under the **Apache License 2.0**, and a copy of that
license is in `LICENSE` here. The upstream ref is recorded in `SOURCE.txt`.

| Folder | Covers |
|---|---|
| `cli` | `spacetime` CLI commands |
| `concepts` | core concepts: tables, reducers, subscriptions, identity |
| `rust-server` | Rust modules, including 2.14 async inter-database calls |
| `typescript-server` | TypeScript modules |
| `csharp-server` | C# modules |
| `cpp-server` | C++ modules |
| `typescript-client` | TypeScript/React client SDK |
| `csharp-client` | C# client SDK |
| `unity` | Unity integration |
| `unreal` | Unreal Engine integration |
| `mcp` | SpacetimeDB MCP server |

- **Precedence:** where a kit skill (`skills/stdb-*`) and an official skill disagree on an API, the official skill at
  the pinned version wins. Please file an issue so the kit skill can be fixed.
- **Updating:** run `python tools/kit.py vendor-skills [--ref <tag-or-branch>]`, review the diff, run
  `python tools/kit.py check`, then commit.
- Don't edit these files. Kit-specific guidance belongs in `skills/stdb-*`.

"SpacetimeDB" is a trademark of Clockwork Laboratories, Inc. This kit is not affiliated with or endorsed
by Clockwork Labs.
