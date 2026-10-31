---
name: stdb-observability
description: Add metrics, logs, health and dashboards to a SpacetimeDB world (tick_health, row counts, reducer errors, connection counts) without hurting performance. Use before playtests and for live ops.
---

# Observability

## In the module

- **`tick_health` singleton:** tick count, last/avg/max lateness, level 0-3, online players and moving entities. The
  template has it. Make it public, or admin-only via a view.
- **Counters table** (`stat(name, value, updated_at)`), updated at most every N ticks: joins, leaves, reducer errors by
  name, jobs queued.
- **Logs:** `log::info!` for lifecycle and admin actions. `log::warn!` for rejected inputs, sampled. Never log per
  entity per tick, and never log tokens or secrets.

## Outside

- `spacetime logs <db> -f` for live logs.
- `spacetime sql <db> "SELECT * FROM tick_health"` for ad-hoc checks.
- A watcher client (TypeScript, about 50 lines) subscribes to `tick_health` and counters and pushes them to your
  metrics stack. You can also expose them through the web admin template.
- Host metrics: CPU per core (STDB is single-threaded per database, so watch the hottest core), RSS, disk IO and free
  space.

## Alerts

| Signal | Warn | Page |
|---|---|---|
| tick level | 2 for 1 min | 3 for 30 s |
| reducer error rate | > 1% | > 5% |
| disk free | < 30% | < 15% |
| connect failures | rising | > 10/min |

## Load-test linkage

Every load-test report stores `tick_health` at the end. Compare them across commits. A regression in
`avg_lateness_us` at the same bot count blocks the merge.
