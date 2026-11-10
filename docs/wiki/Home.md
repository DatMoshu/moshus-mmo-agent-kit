# Documentation

These version-controlled pages are the canonical handbook. Read them alongside source at the same commit. An optional GitHub Wiki is a published copy; see [release maintenance](Release-maintenance.md).

## Start a project

1. [Installation](Installation.md): pinned tools, platform limits, and local setup.
2. [First project](First-project.md): compatible templates, scaffolding, and one verified feature.
3. [Architecture](Architecture.md): identity, transactions, subscriptions, and ticks.
4. [Server and client templates](Server-and-client-templates.md): schema families and evidence.

## Develop and verify

- [Agent workflows](Agent-workflows.md): routing, implementation contract, and handoff.
- [Recipes](Recipes.md): chat, inventory, AOI, operators, idempotency, sidecars, and handoff.
- [Testing](Testing.md): what each gate proves and what it cannot establish.
- [Troubleshooting](Troubleshooting.md): toolchain, publishing, binding, and session failures.
- [Version upgrades](Version-upgrades.md): coordinated pins and schema compatibility.

## Maintain and release

- [Security](Security.md): authority, visibility, admission, and external playtests.
- [Contribution](Contribution.md): source/licensing rules and review expectations.
- [Release maintenance](Release-maintenance.md): candidate evidence and wiki sync.

The [README](../../README.md) gives the shortest overview. Detailed references remain authoritative for their topics: [shard core contract](../SHARD_CORE.md), [decision tree](../decision-tree.md), [scale planning](../scale-ladder.md), [licensing](../legal/LICENSING.md), and [dated verification records](../VERIFICATION.md).

An example's existence means source is available; only a dated run establishes what was exercised. Do not apply old platform results to a new checkout without rerunning them.
