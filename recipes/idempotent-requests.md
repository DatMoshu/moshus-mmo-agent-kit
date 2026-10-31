# Idempotent requests

Since 2.13, an HTTP reducer call that times out returns 504 and **the outcome is unknown**: the call may have committed.
IDC delivery also retries. Any reducer called by something that retries must therefore be safe to run twice.

Code: [`snippets/idempotent.rs`](snippets/idempotent.rs) (uses `add_items` from the inventory recipe).

1. The caller picks a `request_id` (a UUID, or a natural key such as `order-123:line-2`) and **reuses it on every retry**.
2. The reducer inserts the id into a private `applied_request` table in the same transaction as the effect.
   If the id is already there, it returns `Ok(())` without doing anything.
3. If the effect fails, the id insert rolls back with it, so a retry can still succeed later.

**Checked (2026-10-31):** Calling `grant_purchase "order-1"` twice granted once.

**Housekeeping:** prune `applied_request` rows older than your longest retry window. Use a scheduled reducer, as
the starter's `HOUSEKEEPING_EVERY` does.

IDC-called reducers in the sharded template use the same idea, keyed by `handoff_key`.
