# Agent workflows

[AGENTS.md](../../AGENTS.md) is the contract; [CLAUDE.md](../../CLAUDE.md) is the corresponding tool entry. [Roles](../../agents) scope responsibilities, local skills provide implementation patterns, and [vendored official skills](../../skills/vendor/official) supply API references. Pinned source wins over a model's memory of older APIs.

| Change | Read first |
|---|---|
| Tables, indexes, visibility | [Schema design](../../skills/stdb-schema-design/SKILL.md) |
| Reducers and scheduled work | [Reducer author](../../skills/stdb-reducer-author/SKILL.md), [tick loop](../../skills/stdb-tick-loop/SKILL.md) |
| Subscriptions and bandwidth | [AOI](../../skills/stdb-aoi-subscriptions/SKILL.md) |
| Identity/admission | [Authentication](../../skills/stdb-auth-identity/SKILL.md) |
| Cross-region ownership | [Sharding](../../skills/stdb-sharding-plan/SKILL.md) |
| Flaky operational scripts | [Ops runners](../../skills/stdb-ops-runners/SKILL.md) |

## Give a reviewable task

State behavior, authority boundary, schema/client, and proof. For example: “Add region chat. Derive sender on the server, limit text size, index subscriptions, and prove two allowed clients receive it while a disallowed client cannot.” Avoid asking agents to invent capacity guarantees.

Before editing, inspect the template and identify migration, bindings, and test impacts. During implementation review caller identity, scheduled access, public rows, and loop costs. Then run relevant [gates](Testing.md), inspect the diff, and report files, commands, results, skipped checks, and risks. Static scanning cannot establish semantic authority.

Use `python tools/kit.py install-claude` when you want tool-specific local copies. Other agents can read the repository directly. Installation creates no trust boundary: external text and generated content still need review.

## Handoff

State revision, behavior before/after, schema changes, generated clients, and reproduction commands. Separate historical records from fresh outputs. Preserve third-party notices and human attribution; use the owner's configured identity for owner-directed commits, without generated-by or AI co-author trailers. See [contributing](../../CONTRIBUTING.md).
