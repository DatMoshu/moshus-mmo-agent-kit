---
name: stdb-load-test
description: Run headless bot swarms against a SpacetimeDB world and gate on budgets (PASS/CONCERNS/FAIL). Use before milestones and playtests, and after changes to the tick, AOI or hot tables.
---

# Load testing

## Run

```
python tools/kit.py loadtest --bots 100 --duration 30
```

- The bots (`tools/loadtest/bots`, TypeScript SDK) connect with fresh identities. Each one joins, subscribes to its own
  transform and then its 3x3 AOI cells, and sends movement intents at a human rate.
- The report goes to `tools/loadtest/bots/reports/loadtest-<N>bots.json`. It contains bots ready, connect failures,
  reducer errors, reducer p95/p99, `tick_health`, rows received and `updates_per_bot_per_sec`.
- Verdicts come from `tools/loadtest/budgets.json` (warn/fail per metric).

## Ladder

Follow `docs/scale-ladder.md`.

| Rung | Bots | Where | Must show |
|---|---|---|---|
| 1 | 10 | dev machine | everything works, 0 errors |
| 2 | 100 | dev machine | PASS on budgets; updates per bot per second recorded |
| 3 | 500-1,000 | production-like host, one region | tick level <= 1; this is your region ceiling |
| 4 | 2,000-5,000 | multiple regions | handoffs under load, no lost or duplicated players |

Bots on the same machine as the server compete for CPU. For rungs 3 and up, run bots from other machines (shard the
bot count across hosts) and quote the server hardware.

## Reading results

- **Reducer p95 high, tick level 0:** contention from bursty client calls. Batch inputs and lower the send rate.
- **Tick lateness rising:** too much per-tick work. Shed, budget, or move work to a sidecar.
- **Updates per bot per second high:** AOI too wide, writes not on change, or the tick rate is too high.
- **Connect failures:** server limits, the OS file descriptor limit, or the admission config.

## Measured anchor

On a dev box: 100 bots, 20 Hz, 3x3 AOI with 50-unit cells, about 1,700 updates per bot per second, p95 about 33 ms,
tick level 0. A Windows workstation with 50 bots showed about 850 updates per bot per second and p99 about 17 ms.
These are reference points, not capacity claims.
