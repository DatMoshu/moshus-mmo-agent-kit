# Contribution and review

[CONTRIBUTING.md](../../CONTRIBUTING.md) is the policy. Keep source/docs aligned at one revision. State behavior, schema/client, the narrow change, and evidence.

- Does the server derive the caller and reject unauthorized/stale requests?
- Are scheduled/IDC entry points guarded and repeatable operations idempotent?
- Are public rows safe for all readers and query columns indexed?
- How does work grow with players/history, and how is it bounded or measured?
- Were affected bindings regenerated together?
- Do results name platform, versions, commands, revision and gaps?
- Is external material traceable, compatible and accompanied by notices?

Docs should use valid relative links, real CLI options, and source-derived diagrams. Do not fabricate screenshots, badges, timing or capacity promises. Contextualize historical results. Keep wiki pages canonical under version control; see [release maintenance](Release-maintenance.md).

Version bumps follow [the upgrade process](Version-upgrades.md); vulnerabilities use [SECURITY.md](../../SECURITY.md). Preserve upstream/human attribution and existing history. Do not append AI credits or rewrite history during ordinary changes.
