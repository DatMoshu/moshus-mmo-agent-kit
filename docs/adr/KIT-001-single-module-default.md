# KIT-001: Default topology is a single module

- Status: accepted
- Date: 2026-10-30

## Context
Most hobby and indie MMOs never exceed one region's capacity (a few hundred concurrent players). Sharding adds handoff protocols, cross-database messaging and operational load.

## Decision
Ship a single-module starter (`templates/server/rust-single`) as the default. Sharding is opt-in, with a guide (`docs/scale-ladder.md`, `skills/stdb-sharding-plan`) and an example (`templates/server/rust-sharded`) to use once a load test requires it.

## Consequences
First run is simple. The single-module template still carries AOI cells, a hot/cold split and tick health, so the path to sharding doesn't need a rewrite.
