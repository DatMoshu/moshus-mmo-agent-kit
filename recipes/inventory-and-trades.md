# Inventory and trades without duplication

Code: [`snippets/inventory.rs`](snippets/inventory.rs). Append it to `templates/server/rust-single/src/lib.rs`
and add `view, ViewContext` to the `use spacetimedb::{...}` line.

## Why it cannot dupe

A reducer is one transaction. `give_item` calls `take_items` and then `add_items`. If any check fails
(too few items, too far, bad quantity), the reducer returns `Err` and **every** write in that call is rolled back.
Never split a transfer across two reducers or two client calls. If a transfer spans **databases**
(sharded worlds), use the lock → offer → accept → delete → activate protocol from `templates/server/rust-sharded`.

## Shape

* `item_def` (public): static definitions. Seed them with an admin reducer, or with idempotent `ensure_*` code
  (because `init` only runs on the first publish).
* `inventory` (private, indexed by owner): stacks. Each player reads only their own stacks through the `my_inventory` view.
* `give_item(to, item_id, qty)`: the giver is always `ctx.sender()`. It checks admission, quantity bounds and distance.
* `gm_grant`: admin-only, for testing.

## Checked (2026-10-31, local 2.14)

* Compiled against the starter.
* Live run: defining a max stack of 20 and granting 45 gave 20/20/5. A `grant_purchase` replayed with the
  same request id was applied once (total 50).
* Live run with two clients: `give_item` with nothing in range was rejected.
* Not covered: a successful give between two players standing next to each other. To test it, put two bots at the same spot.

## Extending

* Equipment: an `equipped` table keyed by `(owner, slot)`. Equipping is one reducer that moves a stack between tables.
* Trades: a `trade_offer` table plus `accept_trade`, which re-validates both sides and swaps everything inside one reducer.
* Item ids are `u32` from `item_def`. Never accept item names from clients.
