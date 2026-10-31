# Scale ladder: 10 to 5,000 concurrent players

Climb one rung at a time. Each rung lists what changes, what to measure and the gate to pass before the next rung.
Numbers are **planning estimates** for a typical action game with movement at 10-20 Hz. Your game will differ, so
the load test is the only source of truth. Record every gate run in `docs/VERIFICATION.md` with hardware and versions.

Two facts drive the whole ladder:

- Each SpacetimeDB database is a **single-threaded actor**. All reducers, the tick and subscription evaluation for
  that database share one core.
- What players feel is **fan-out**: rows changed per tick multiplied by the number of subscribers who can see them.

## Rung 10: prototype

- Setup: `rust-single` template, local server, anonymous identities.
- Do: get the core loop fun. Keep the hot/cold split and AOI cells from the template even if they seem unnecessary.
- Gate: `python tools/kit.py smoke` passes. Two humans can play.

## Rung 50: friends playtest

- Add: saved tokens, admission allow-list, a backup before each session, `tick_health` on a dashboard
  (`templates/client/web-admin`).
- Measure: `loadtest --bots 50 --duration 60`.
- Gate: PASS, average tick lateness < 5 ms, no reducer errors. A restore drill has been done once.

## Rung 200: public alpha

- Add: OIDC auth, rate limits on chat and other spammy reducers, write-on-change and position quantization, and
  per-cell subscriptions sized to the view radius.
- Measure: `loadtest --bots 200 --duration 300`. Watch updates per bot per second as well as tick lateness.
- Gate: PASS, p99 reducer latency < 50 ms, lateness level stays 0. Updates per bot per second have a budget you
  chose (the reference template measured ~1,700/s with 100 bots in one crowd; quantizing and lower send rates
  for distant entities bring it down a lot).

## Rung 500: one full region

- This is around the practical ceiling of one database for a busy world (estimate).
- Add: tick budget per system, housekeeping that sheds at load level >= 2, interest tiers (near = every tick, far =
  every few ticks), views or visibility filters for private data, and a sidecar for anything slow.
- Measure: `loadtest --bots 500 --duration 600` on hardware like production, with a realistic mix of behaviors.
- Gate: PASS with headroom (average lateness < 10% of the tick interval). If you can't get there, profile the hot
  reducers before sharding. Sharding multiplies complexity.

## Rung 1,000: sharded world

- Topology: one **global** database (accounts, social, economy, region directory) and **region** databases split
  by space. Players connect to one region at a time. See `templates/server/rust-sharded` and
  `skills/stdb-sharding-plan`.
- Cross-database messages use 2.14 inter-database communication (IDC): outbox tables with `on_result` handlers,
  idempotent message ids, and allow-listed sender identities. IDC requires the databases to be on the **same
  server**.
- Handoff protocol: lock in source, offer to target, accept, delete in source, activate in target, then the client
  reconnects.
- Gate: all regions PASS their own rung-500 gate at their share of players, handoff loss is 0 in 1,000 scripted
  crossings, and the global database lateness stays low under login storms.

## Rung 5,000: many regions, many machines

- Topology: 10+ regions, global split by function (identity, economy, chat), a gateway or directory service that
  routes logins, and sidecars for matchmaking, analytics and moderation.
- Hard limits to plan around:
  - IDC works only within one SpacetimeDB server, so regions on different machines need a relay (a sidecar
    that subscribes to one database and calls reducers on another, with idempotency).
  - The BSL 1.1 Additional Use Grant covers one production instance. Several self-hosted instances need a commercial
    license from Clockwork Labs, or Maincloud. See `docs/legal/LICENSING.md`.
- Gate: a soak test at target load for hours, a region failure and restore drill, and a full backup restore of the
  global database within your recovery-time target.

## Levers, cheapest first

1. Write only on change, and quantize positions and rotations.
2. Smaller AOI cells, or fewer subscribed cells, for fast-moving entities.
3. Lower tick rate for far or idle entities. Tiered interest.
4. Move cold data and history out of hot tables.
5. Batch inputs (one reducer call per client per tick, not per keypress).
6. Move slow or external work to sidecars or procedures.
7. Only then: shard by region, then split global by function.
