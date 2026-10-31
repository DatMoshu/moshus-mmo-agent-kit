---
name: stdb-unreal-client
description: Build an Unreal Engine client for a SpacetimeDB world with the official Unreal SDK plugin (singleton connection actor, FrameTick, unrealcpp codegen, AOI). Use for Unreal client work.
---

# Unreal client

Official reference: `skills/vendor/official/unreal/SKILL.md`. Kit starter: `templates/client/unreal` (thin C++
classes; see its README for status).

## Setup

1. Copy the `SpacetimeDbSdk` plugin, matching `stdb.lock`, into `Plugins/`. Regenerate project files. Add
   `"SpacetimeDbSdk"` to `PublicDependencyModuleNames` in your `Build.cs`.
2. Generate bindings:
   ```
   spacetime generate --lang unrealcpp --uproject-dir <dir> --module-path <server> --unreal-module-name <Module>
   ```
3. Add a singleton connection actor (or GameInstance subsystem) that builds the connection with
   `UDbConnection::Builder()->WithUri(...)->WithDatabaseName(...)`, binds the connect and disconnect delegates, and has
   ticking enabled so `FrameTick` runs every frame.

## Rules

- Delegates bound with `UFUNCTION()` handlers. Keep the connection pointer in a `UPROPERTY()` so GC keeps it.
- Subscriptions: your own row, then per-cell AOI queries. Diff cells on crossing.
- Only the connection actor touches the SDK. Gameplay reads through an adapter component.
- Persist the token per profile in `Saved/` config, never in the repo.
- Regenerate bindings after every module change. A stale header means a confusing compile or runtime mismatch.

## Test

- PIE with two clients (Net Mode: Standalone, 2 players) against a local server, plus the kit's TS bots for load.
