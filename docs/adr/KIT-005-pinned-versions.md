# KIT-005: One pinned versions file

- Status: accepted
- Date: 2026-10-30

## Context
Floating "latest" versions broke builds repeatedly: CLI, server, crate and SDK versions drifted apart, and agents wrote code for APIs from other versions.

## Decision
`stdb.lock` pins the CLI, server, crate, SDKs and toolchain. `tools/kit.py` reads it. Bumps follow `docs/processes/version-bump.md`.

## Consequences
Upgrades are deliberate and cost an evidence run. The hallucination catalog is updated with each bump.
