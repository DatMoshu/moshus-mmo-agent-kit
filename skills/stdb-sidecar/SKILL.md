---
name: stdb-sidecar
description: Offload heavy or impure work (pathfinding, mapgen, LLM/NPC brains, external APIs, batch jobs) from a SpacetimeDB module to a sidecar service that talks to the database as a privileged client. Use when work doesn't fit the tick budget or needs I/O.
---

# Sidecar pattern

## When

- The work is too slow for the tick: pathfinding over large maps, worldgen, physics bakes.
- It needs I/O a reducer can't do: external APIs, LLMs, payment webhooks, file export.
- It is batch or analytics work that shouldn't block players.

Inside a module, `#[procedure]` with `ctx.http` covers small outbound HTTP calls. Use a sidecar for anything longer,
stateful or CPU-heavy.

## Shape

```
module  --insert-->  job (private)          sidecar subscribes to job WHERE status='queued'
sidecar --calls--->  claim_job(id)          service-only reducer; sets status='running', worker
sidecar --does work, then calls--> complete_job(id, result)   service-only; validates, applies
module  scheduled sweep: running jobs older than T -> queued again (attempts+1) or failed
```

- **Service identity:** the sidecar uses its own long-lived token, stored outside the repo. The module stores its
  identity in a private `service_account` table, set by an admin reducer. Service reducers start with
  `require_service(ctx)?`.
- **Idempotent results:** `complete_job` ignores jobs that are not `running` or are claimed by another worker.
- **Never trust sidecar output blindly.** Validate it in the reducer: bounds, ownership and size.
- **Backpressure:** cap queued jobs per player and per type, and drop or merge duplicates.

## Template

`templates/sidecar` is a TypeScript worker with this loop: connect, subscribe to queued jobs, claim, work, complete,
reconnect with backoff. Pair it with the job tables shown in its README.

## Gotchas

- A subscription can deliver a job to several sidecars at once. The claim reducer is the lock.
- On restart the sidecar resubscribes and must not double-process jobs. Rely on `claim_job` and job status.
- Don't put game rules in the sidecar. It computes; the module decides.
