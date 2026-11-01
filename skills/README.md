# Skills

Skills are task playbooks. Each one is a folder with a `SKILL.md` that has YAML frontmatter (`name`, `description`)
and a markdown body. Claude Code, Cursor, Codex and similar agents can load them directly. Agents in `agents/` list the
skills they load.

## Kit skills (23)

They are written for SpacetimeDB **2.14** (see `stdb.lock`) and come from real projects and measured load tests.

| Skill | Use it when |
|---|---|
| [`stdb-aoi-subscriptions`](stdb-aoi-subscriptions/SKILL.md) | Implement cell-based interest management (AOI) for SpacetimeDB worlds on server and client, and measure its bandwidth. Use for any world with more than about 50 entities or when bandwidth grows with player count. |
| [`stdb-auth-identity`](stdb-auth-identity/SKILL.md) | Wire player identity, login (OIDC issuers such as SpacetimeAuth or a token broker), accounts, admin powers and server-side admission in SpacetimeDB 2.14. Use before any external playtest or when adding login. |
| [`stdb-bindings-regen`](stdb-bindings-regen/SKILL.md) | Regenerate and verify client bindings for every client (TypeScript, Godot, C#, Unreal) after a module change. Use after every publish that changes tables, reducers or types. |
| [`stdb-deploy-maincloud`](stdb-deploy-maincloud/SKILL.md) | Publish a SpacetimeDB module to Maincloud (Clockwork Labs' hosted service) and point clients at it. Use for zero-ops hosting or when the self-host license limits matter. |
| [`stdb-deploy-selfhost`](stdb-deploy-selfhost/SKILL.md) | Run a pinned standalone SpacetimeDB server on your own Linux host with TLS, backups, upgrades and monitoring. Use when you go beyond localhost without Maincloud. |
| [`stdb-godot-client`](stdb-godot-client/SKILL.md) | Build a Godot 4.7 client for a SpacetimeDB world with the community flametime GDScript SDK (net facade, AOI subscriptions, identity profiles, headless smoke tests). Use for any Godot client work. |
| [`stdb-hallucination-check`](stdb-hallucination-check/SKILL.md) | Catch invented or outdated SpacetimeDB APIs (1.x syntax, wrong attributes, impure calls) in code and docs before they ship. Use after any AI-written module or client code, and in CI. |
| [`stdb-license-check`](stdb-license-check/SKILL.md) | Check SpacetimeDB BSL limits, kit/asset/dependency licenses and game-IP risks before publishing a game, repo or hosted world. Not legal advice. Use before launch, open-sourcing, or using third-party content. |
| [`stdb-load-test`](stdb-load-test/SKILL.md) | Run headless bot swarms against a SpacetimeDB world and gate on budgets (PASS/CONCERNS/FAIL). Use before milestones and playtests, and after changes to the tick, AOI or hot tables. |
| [`stdb-migration`](stdb-migration/SKILL.md) | Ship SpacetimeDB schema changes to a world that already has data, without wipes. Use when changing tables after players exist. |
| [`stdb-new-game`](stdb-new-game/SKILL.md) | Scaffold a new SpacetimeDB 2.14 MMO from the kit (server module, chosen client, pinned versions, smoke test). Use when starting a project or a fresh prototype. |
| [`stdb-observability`](stdb-observability/SKILL.md) | Add metrics, logs, health and dashboards to a SpacetimeDB world (tick_health, row counts, reducer errors, connection counts) without hurting performance. Use before playtests and for live ops. |
| [`stdb-ops-runners`](stdb-ops-runners/SKILL.md) | Write or fix ops runners (publish, smoke, load test, backup, migration batches, deploy scripts) so they are idempotent, retry only transient failures with backoff, resume from receipts and read JSON with a BOM safely. Use when a scripted run against a SpacetimeDB server fails halfway, flakes, or needs a rerun. |
| [`stdb-reducer-author`](stdb-reducer-author/SKILL.md) | Write correct SpacetimeDB 2.14 Rust reducers with authority checks, input validation, deterministic logic and rollback. Use for any reducer you add or change. |
| [`stdb-schema-design`](stdb-schema-design/SKILL.md) | Design SpacetimeDB tables, keys, indexes, visibility and AOI columns for a feature before writing reducers. Use for any new system or table. |
| [`stdb-security-review`](stdb-security-review/SKILL.md) | Audit a SpacetimeDB module and its clients for authority, visibility, input validation, abuse and secret handling before playtests and releases. Use before any external exposure. |
| [`stdb-sharding-plan`](stdb-sharding-plan/SKILL.md) | Decide when and how to split a SpacetimeDB world into a global database plus region databases, using 2.14 async inter-database calls (outbox tables) and an idempotent handoff. Use when a single region hits its measured ceiling or a design clearly needs regions. |
| [`stdb-sidecar`](stdb-sidecar/SKILL.md) | Offload heavy or impure work (pathfinding, mapgen, LLM/NPC brains, external APIs, batch jobs) from a SpacetimeDB module to a sidecar service that talks to the database as a privileged client. Use when work doesn't fit the tick budget or needs I/O. |
| [`stdb-tick-loop`](stdb-tick-loop/SKILL.md) | Add or change a fixed-rate scheduled game tick with self-measured health and load shedding in SpacetimeDB 2.14. Use for real-time simulation, AI, regen or any periodic work. |
| [`stdb-unity-client`](stdb-unity-client/SKILL.md) | Build a Unity client for a SpacetimeDB world with the official C# SDK (connection manager, FrameTick, token persistence, AOI, codegen). Use for Unity client work. |
| [`stdb-unreal-client`](stdb-unreal-client/SKILL.md) | Build an Unreal Engine client for a SpacetimeDB world with the official Unreal SDK plugin (singleton connection actor, FrameTick, unrealcpp codegen, AOI). Use for Unreal client work. |
| [`stdb-upgrade-runtime`](stdb-upgrade-runtime/SKILL.md) | Upgrade the pinned SpacetimeDB version (CLI, server, crate, SDKs) with a side-by-side rehearsal and a rollback. Use when a new SpacetimeDB release lands or a bug fix is needed. |
| [`stdb-web-client`](stdb-web-client/SKILL.md) | Build browser clients, admin consoles and bots with the SpacetimeDB TypeScript SDK (React hooks or the plain connection API, AOI subscriptions, reconnection). Use for web games, admin tools, dashboards and load bots. |

## Official skills (vendored)

`vendor/official/` holds the 11 Apache-2.0 skills published by Clockwork Labs: cli, concepts, rust-server,
typescript-server, csharp-server, cpp-server, typescript-client, csharp-client, unity, unreal and mcp. They are
unmodified. Attribution is in `vendor/official/ATTRIBUTION.md`, and you can refresh them with
`python tools/kit.py vendor-skills`. **On API details, the official skills at the pinned version win.**

## Using with your agent

- **Claude Code:** `python tools/kit.py install-claude [--dest <project>]` copies the agents into `.claude/agents/`,
  and the kit and official skills into `.claude/skills/`. `CLAUDE.md` points at `AGENTS.md`.
- **Cursor / Codex / others:** `AGENTS.md` routes tasks to skills by path. Agents read `skills/<name>/SKILL.md` on
  demand.

## Writing a new skill

1. Copy an existing kit skill folder and rename it `stdb-<verb-noun>`.
2. Keep the frontmatter `description` to one or two sentences: what it does, then "Use when ...".
3. Include steps, 2.14-correct code, a wrong-vs-right table if APIs are involved, gates (how you know it's done) and
   the handoff.
4. Run `python tools/kit.py check`. In markdown, only fenced code blocks are scanned, so put wrong examples in prose
   or tables, or wrap them in `kit:allow-begin` / `kit:allow-end` comments.
