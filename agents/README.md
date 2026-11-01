# Agents

Role definitions usable as Claude Code subagents (`python tools/kit.py install-claude`) or as plain role prompts in any runtime.

| Agent | Model hint | Use for |
|---|---|---|
| [stdb-architect](stdb-architect.md) | opus | Owns topology, schema shape and the scale plan for a SpacetimeDB MMO |
| [module-engineer](module-engineer.md) | sonnet | Writes and changes SpacetimeDB 2.14 module code (Rust first, TypeScript second): tables, reducers, scheduled jobs, views, procedures |
| [netcode-engineer](netcode-engineer.md) | sonnet | Owns interest management, subscription design, update rates, quantization and client prediction for SpacetimeDB worlds |
| [client-engineer-godot](client-engineer-godot.md) | sonnet | Integrates Godot 4.7 clients with SpacetimeDB through the vendored GDScript SDK and a single Net seam |
| [client-engineer-unity](client-engineer-unity.md) | sonnet | Integrates Unity clients with SpacetimeDB through the official C# SDK |
| [client-engineer-unreal](client-engineer-unreal.md) | sonnet | Integrates Unreal Engine clients with SpacetimeDB through the official Unreal SDK (C++ and Blueprint) |
| [client-engineer-web](client-engineer-web.md) | sonnet | Builds TypeScript/React web clients, admin panels and bot clients on the spacetimedb npm SDK |
| [gameplay-systems-designer](gameplay-systems-designer.md) | sonnet | Turns game mechanics (combat, crafting, economy, progression, quests) into server-authoritative tables and reducers |
| [security-auditor](security-auditor.md) | opus | Reviews SpacetimeDB modules for authority holes, admission bugs, data leaks and abuse |
| [load-test-engineer](load-test-engineer.md) | sonnet | Owns bot clients, load budgets and the PASS/CONCERNS/FAIL gate |
| [live-ops-engineer](live-ops-engineer.md) | sonnet | Deploys, upgrades, backs up and monitors SpacetimeDB worlds (self-hosted standalone or Maincloud) |
| [data-migration-specialist](data-migration-specialist.md) | sonnet | Plans and runs schema evolution on live SpacetimeDB worlds without wipes |
| [procgen-engineer](procgen-engineer.md) | sonnet | Builds deterministic world generation (terrain, dungeons, loot tables) that matches across server, tools and tests |
| [sharding-specialist](sharding-specialist.md) | opus | Designs global + region database splits and cross-database handoffs using SpacetimeDB 2.14 inter-database calls |
| [license-steward](license-steward.md) | sonnet | Guards IP and license hygiene: SpacetimeDB BSL terms, Apache/MIT attribution, GPL quarantine and licensed game data |
| [producer](producer.md) | sonnet | Owns milestones, acceptance evidence and stop rules for an MMO project |
| [stdb-docs-librarian](stdb-docs-librarian.md) | sonnet | Keeps the kit's knowledge current: version pins, vendored official skills, hallucination catalog and KB |
| [qa-playtest-lead](qa-playtest-lead.md) | sonnet | Writes human playtest scripts, runs two-identity checks and triages bugs |
