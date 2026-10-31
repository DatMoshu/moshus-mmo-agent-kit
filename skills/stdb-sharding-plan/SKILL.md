---
name: stdb-sharding-plan
description: Decide when and how to split a SpacetimeDB world into a global database plus region databases, using 2.14 async inter-database calls (outbox tables) and an idempotent handoff. Use when a single region hits its measured ceiling or a design clearly needs regions.
---

# Sharding plan: global + regions

## Should you?

- A database is a single-threaded actor. A good working ceiling is about **500 concurrently active players per
  region** (ESTIMATE, based on public reports from a live STDB MMO). Your own load test sets the real number.
- Shard only after rung 3 of `docs/scale-ladder.md` shows the ceiling, or when the design needs isolated regions.
- **License:** the SpacetimeDB BSL grant covers one production instance. Multiple databases on one standalone
  instance is a different question from multi-host. Check `docs/legal/LICENSING.md` and ask Clockwork Labs before
  launch.

## Split

| Global database | Region databases |
|---|---|
| accounts, auth, bans | spatial simulation: transforms, mobs, resources |
| region directory (which region owns which player) | per-region chat/events |
| economy ledger, trade escrow, mail | local inventories while in region (or keep in global) |
| global chat, guilds | |

Clients connect to the global database plus their current region, and switch region subscriptions on handoff.

## 2.14 inter-database calls (IDC)

- **Same server only in 2.14.0.** Dependent databases must run on the same SpacetimeDB server.
- Declare the graph in `spacetime.json` with `"dependencies": [{"name": "region", "database": "region-1"}]` and
  `"children"`. Then run `spacetime generate <sending-db>`. Rust bindings land in `src/remote_bindings/`.
- **Outbox table** (one per remote reducer):
  ```rust
  mod remote_bindings;
  use remote_bindings::region;

  #[table(accessor = offer_outbox, outbox(region::accept_transfer))]
  pub struct OfferOutbox {
      #[primary_key] #[auto_inc] msg_id: u64,   // exactly one u64 auto_inc PK
      #[target] target: region::Identity,      // exactly one target
      transfer_id: u64,                        // columns = remote reducer params (same names/types)
      player: Identity,
      x: f32, y: f32,
  }
  ```
  Wrap a plain identity with `region::Identity(id)`.
- **Delivery:** sent only if the sending transaction commits; runs exactly once; ordered per outbox and target. Rows
  are insert-only, so you cannot cancel a pending call.
- **Result:** `#[reducer(on_result(offer_outbox))] fn on_offer(ctx, row: OfferOutbox, result: Result<(), String>)`.
  Drive the next step from here.
- **Receiver:** an ordinary reducer.
  - `ctx.sender()` is the *sending database's* identity, so check it against an allow-list.
  - The receiver runs `client_connected`/`client_disconnected` around each delivered call without a JWT. If
    `client_connected` rejects the sender database, the call is **retried forever**. Allow known database identities
    there.
- Index lookups on a remote `Identity` column don't compile. Iterate and compare.
- When a remote reducer's parameters change, regenerate bindings and republish the sender.

## Handoff protocol (no cross-database transactions)

```
source: lock      player.in_transit = transfer_id; stop simulating them          (one txn)
source: offer     insert outbox row -> target.accept_transfer(transfer_id, snapshot)
target: accept    if transfer_id seen: return Ok (idempotent); else insert inactive copy + ack
source: on_result Ok  -> delete source row; insert outbox -> target.activate(transfer_id)
                  Err -> unlock (in_transit = none), player stays in source
target: activate  mark active; client switches its region subscription
sweeper:          transfers stuck > T seconds are reconciled from the directory in global
```

Every step is keyed by `transfer_id` and safe to repeat. Test duplicate delivery, a target restart mid-offer, a
rejected accept, and a client disconnect during transit.

## Template

`templates/server/rust-sharded` implements a global directory plus regions with this handoff. Check its README for
verification status.
