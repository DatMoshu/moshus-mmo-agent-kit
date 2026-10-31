---
name: stdb-web-client
description: Build browser clients, admin consoles and bots with the SpacetimeDB TypeScript SDK (React hooks or the plain connection API, AOI subscriptions, reconnection). Use for web games, admin tools, dashboards and load bots.
---

# Web / TypeScript client

Official reference: `skills/vendor/official/typescript-client/SKILL.md`. Kit code: `templates/client/web-admin` (a
React admin console) and `tools/loadtest/bots` (plain TypeScript bots).

## Connection

```ts
import { DbConnection } from './module_bindings';

const conn = DbConnection.builder()
  .withUri(import.meta.env.VITE_STDB_URI)
  .withDatabaseName(import.meta.env.VITE_STDB_DB)
  .withToken(localStorage.getItem(TOKEN_KEY) ?? undefined)
  .onConnect((_c, identity, token) => localStorage.setItem(TOKEN_KEY, token))
  .build();
```

- Bindings come from `spacetime generate --lang typescript --out-dir src/module_bindings --module-path <server>`
  (`python tools/kit.py bindings`).
- **React:** wrap the app in `SpacetimeDBProvider`. `useTable(tables.x)` owns its subscription and readiness. Don't
  add a second subscription for the same query. Rows are readonly, so copy before sorting.
- **Plain API:** `conn.subscriptionBuilder().onApplied(...).subscribe([...queries])`. Keep the handle and call
  `unsubscribe()` when leaving a cell.
- **Reconnect:** `onConnect` runs again after recovery. Register callbacks and subscriptions once, outside it. Don't
  build your own retry loop while automatic recovery is pending.

## Admin consoles

- The admin identity is whoever holds the admin token. Load it from a local file or a login, never from the bundle.
- Every admin action is a `require_admin` reducer. The UI is only a convenience.
- Read-only dashboards subscribe to `tick_health`, counters and `world_config`.

## Bots

- One `DbConnection` per bot, a fresh identity each (no token), staggered connects (20-50 ms apart), and human-rate
  inputs.
- Count inserts and updates in row callbacks to measure AOI bandwidth.
