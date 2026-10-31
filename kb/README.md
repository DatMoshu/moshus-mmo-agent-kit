# kb: public STDB knowledge base

Curated, **public-only** knowledge about building MMOs on SpacetimeDB 2.x. It is what the kit's agents and
skills were distilled from. Every row is either from public sources (official docs and skills, release notes,
vendor posts that are linked and paraphrased, Apache/MIT reference repos), or is field experience rewritten in generic form.

| File | Rows | What |
|---|---|---|
| `facts.json` | atomic claims | `confidence` = VENDOR CLAIM / MEASURED / DOCUMENTED / LOCAL / ESTIMATE / UNVERIFIED, plus `evidence` |
| `gotchas.json` | symptom → cause → fix | severity and affected versions |
| `patterns.json` | problem → solution → trade-offs | MMO architecture patterns |
| `processes.json` | step lists | milestones, upgrades, playtests, load-test cadence, incidents, backups |
| `decisions.json` | kit ADRs | why the kit looks the way it does |
| `versions.json` | release notes digest | 2.12–2.14 and the Godot SDK |
| `sources.json` | links | license and redistribution rule for each source (`link_only` means summarize and link, never copy) |

Build a queryable SQLite copy (`stdb-kb.sqlite`, git-ignored):

```bash
python tools/kit.py kb-export
sqlite3 kb/stdb-kb.sqlite "select title, fix from gotchas where severity = 'high'"
```

`kb-export` refuses to run if any row is not `visibility = public`.

**Trust levels.** Treat VENDOR CLAIM and ESTIMATE rows as hypotheses: measure on your own workload
(`skills/stdb-load-test`). UNVERIFIED rows must be checked before you rely on them. All rows are dated 2026-10-30 (`as_of`).

The `stdb-docs-librarian` agent keeps this folder fresh: re-check facts on every SpacetimeDB release.
