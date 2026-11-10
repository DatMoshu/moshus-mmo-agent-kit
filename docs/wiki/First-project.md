# First project

First prove the unmodified movement world using [installation](Installation.md). Keep its passing output so you can distinguish environment problems from feature changes.

## Choose a schema family

Use rust-single with Godot, web-admin, or movement bots. ts-single implements the movement schema as an alternative. Use rust-shard with godot-shard for tile maps, seeded NPCs, combat, and inventory. rust-sharded has separate global/region orchestration and a hop client. Similar names do not imply wire compatibility; consult [the template guide](Server-and-client-templates.md).

```sh
python tools/kit.py new my-game --dest ..
```

This creates a sibling directory and refuses to overwrite an existing destination. It copies server/client, tools, docs, roles, rules, skills, and notices. The generated lock changes the module path to `server` and selects a project-specific development database. Check configuration before publishing. Scaffolding copies files; it does not prove every template combination works.

With the local server running:

```sh
cd ../my-game
python tools/kit.py doctor
python tools/kit.py publish
python tools/kit.py smoke
```

When sharing an endpoint, use a distinct database consistently for publish, bindings, and tests. Confirm supported options with `--help`.

## Add one small feature

Start with [chat](../../recipes/chat.md) or [idempotent requests](../../recipes/idempotent-requests.md). Ask your agent to read AGENTS.md and the relevant local skill, identify affected tables/reducers/subscriptions, and implement a narrow change. Review identity, visibility, indexes, validation, and every loop that grows with players.

Build, publish, regenerate bindings, and repeat smoke. Add feature-specific assertions: movement smoke cannot prove chat privacy or trade atomicity. Record skipped checks and reasons. See [agent workflows](Agent-workflows.md) and [testing](Testing.md).

For tile worlds:

```sh
python tools/kit.py new my-rpg --server rust-shard --client godot-shard
```

Follow the printed fixture instructions and [SHARD_CORE.md](../SHARD_CORE.md). Meadowmere is synthetic test content. Keep game adapters, licensed assets, and game-specific rules outside the reusable core, and track source revisions for vendored updates.
