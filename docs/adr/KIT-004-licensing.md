# KIT-004: Kit licensing and what may be copied

- Status: accepted
- Date: 2026-10-30

## Context
The kit must be shareable. SpacetimeDB's server is BSL 1.1, while its SDKs and official skills are Apache-2.0. Many game reimplementations are GPL, and commercial game content is copyrighted.

## Decision
Kit content is original or derived from Apache/MIT sources with attribution in `NOTICE`. BSL server code and vendor blog posts are linked, not copied. GPL code and licensed game content are never copied, only described.

## Consequences
A `NOTICE` file and vendored LICENSE files are required. `skills/stdb-license-check` and `docs/legal/LICENSING.md` help users do the same.
