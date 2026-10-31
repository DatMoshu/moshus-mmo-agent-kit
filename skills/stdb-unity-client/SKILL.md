---
name: stdb-unity-client
description: Build a Unity client for a SpacetimeDB world with the official C# SDK (connection manager, FrameTick, token persistence, AOI, codegen). Use for Unity client work.
---

# Unity client

Official reference: `skills/vendor/official/unity/SKILL.md` and `skills/vendor/official/csharp-client/SKILL.md`.
Kit starter: `templates/client/unity` (thin scripts; see its README for status).

## Setup

1. Package Manager > Add package from git URL:
   `https://github.com/clockworklabs/com.clockworklabs.spacetimedbsdk.git`. Pin the tag that matches `stdb.lock`.
2. Generate bindings:
   `spacetime generate --lang csharp --out-dir Assets/SpacetimeDB/module_bindings --module-path <server>`.
3. Add a `SpacetimeManager` MonoBehaviour (singleton, `DontDestroyOnLoad`) that builds the connection:
   ```csharp
   Conn = DbConnection.Builder()
       .WithUri(serverUri)
       .WithDatabaseName(databaseName)
       .WithToken(PlayerPrefs.GetString(TokenKey, null))
       .OnConnect(OnConnected)
       .Build();
   ```

## Rules

- **Call `Conn.FrameTick()` in `Update()`.** Without it, no callbacks fire. Main thread only.
- Register row callbacks once after `Build()`. `OnConnected` runs again after each automatic reconnect.
- Save the token in `OnConnected` (PlayerPrefs per profile). Never log it.
- Subscribe to your own row first, then per-cell AOI queries (`stdb-aoi-subscriptions`). Diff the cell set on
  boundary crossing.
- Keep one adapter class between gameplay and the SDK, like the Godot `Net` facade.
- Pending reducer calls may report `Status.UnknownResult` after a disconnect. Make important actions idempotent.

## Test

- Run the kit's TypeScript bots alongside two Unity Editor instances (ParrelSync or a build plus the editor).
- Headless builds (`-batchmode -nographics`) with an autopilot flag can join the smoke test, as the Godot one does.
