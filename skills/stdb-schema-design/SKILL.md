---
name: stdb-schema-design
description: Design SpacetimeDB tables, keys, indexes, visibility and AOI columns for a feature before writing reducers. Use for any new system or table.
---

# Schema design

## When

Before you write reducers for a new system, and whenever a table's write rate or audience changes.

## Method

1. **Name the state.** List each piece of state. For each one, note who writes it, who reads it, and how often it
   changes.
2. **Split by rate.**
   - Hot state goes in narrow tables, for example position, velocity and cell. It changes per tick.
   - Cold state goes in its own tables, for example name, stats, appearance and inventory. It changes on events.
   - Static definitions, such as items and recipes, go in descriptor tables with a generation stamp.
3. **Model entities as components** when objects vary. Use `entity(id)` plus `health(entity_id)`,
   `inventory_slot(entity_id, slot)` and so on. Systems iterate the component table they care about.
4. **Keys.** Every table gets a `#[primary_key]`. The Godot SDK cannot cache keyless rows, and updates go through
   unique indexes. Use `#[unique]` for natural keys such as names.
5. **Indexes.** Every column used in `filter`/`find` or in a subscription `WHERE` gets an index. For multi-column
   indexes use:
   ```rust
   #[table(accessor = entity_transform, public,
           index(accessor = by_cell, btree(columns = [cell_x, cell_y])))]
   ```
   For a single column, use `#[index(btree)]` on the field.
6. **Visibility.**
   - Tables are private unless marked `public`. Make a table public only if every row is fine for every client.
   - Per-player secrets go in a private table plus a per-user view:
     ```rust
     #[view(accessor = my_inventory, public)]
     fn my_inventory(ctx: &ViewContext) -> Vec<InventorySlot> {
         ctx.db.inventory_slot().owner().filter(ctx.sender()).collect()
     }
     ```
     A view needs an index to start from, so `owner` must be indexed.
   - Row-level rules can also use `#[client_visibility_filter]` with `Filter::Sql("... WHERE owner = :sender")`, but
     prefer views. In 2.14.0 RLS needs the `unstable` crate feature, nested `IN (SELECT ...)` is refused, and a
     JOIN-based filter breaks client JOIN subscriptions (`rules/rust-module.md` R30).
7. **AOI keys.** Spatial tables store `cell_x`/`cell_y` (or a chunk id) next to the position, with an index, and update
   them when an entity crosses a cell boundary.
8. **Migration plan.** Ask whether the next change will be additive. Prefer adding tables over adding columns to hot
   tables. A new column on an existing table was refused on 2.13 and disconnects every client on 2.14.0
   (`skills/stdb-migration`).

## Wrong vs right

| Wrong | Right |
|---|---|
| One `entity` table with 40 columns, updated every tick | `entity_transform` (hot, narrow) + `entity_info` (cold) |
| `#[derive(SpacetimeType)]` on a table struct | `#[spacetimedb::table(accessor = x)]` only; `SpacetimeType` is for embedded types |
| `public` table with emails or provider ids | private `account_secret` table, never public |
| Filtering on an unindexed column in the tick | `#[index(btree)]` on it, or restructure |
| Storing derived data that clients can compute | store inputs; compute on client or in a view |

## Output

Write a table map in the PR or ADR. For each table give: name, key, indexes, visibility, writer, write rate, and
expected rows.
