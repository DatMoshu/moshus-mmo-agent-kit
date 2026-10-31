# unity: thin Unity client starter

**Status: PARTIALLY VERIFIED.** The engine-agnostic session logic (`Assets/Scripts/MmoSession.cs`)
and the generated C# bindings compile with .NET 8 + `SpacetimeDB.ClientSDK` 2.14.0, and
`ci/SessionCheck` passed a two-client smoke (join, move, each sees the other move) against both the
Rust and the TypeScript starter modules on Linux. **The Unity editor was not run.** `MmoWorldView.cs`
(the MonoBehaviour) has not been compiled inside Unity.

Built from the official `unity` skill (`skills/vendor/official/unity`), and kept thin on purpose.

## Use it

1. Create a Unity project (2022.3 LTS or Unity 6), or open an existing one.
2. Add the SDK. Merge `Packages/manifest.json` into yours, or use **Window > Package Manager > + > Add package from git URL**:
   `https://github.com/clockworklabs/com.clockworklabs.spacetimedbsdk.git#v2.14.0`. Keep the tag equal to `stdb.lock`.
3. Copy `Assets/Scripts` and `Assets/SpacetimeDB` into your project's `Assets/`.
4. Add an empty GameObject, attach **MmoWorldView**, then set the server URI and database.
5. Press Play and move with WASD. Open a second build or the Godot or web client to see each other.

Regenerate the bindings whenever the module changes:

```bash
spacetime generate --lang csharp --out-dir Assets/SpacetimeDB/module_bindings --module-path <kit>/templates/server/rust-single
```

## What is where

| File | Role |
|---|---|
| `Assets/Scripts/MmoSession.cs` | Connection, subscription, join, change-only movement intent. No UnityEngine types |
| `Assets/Scripts/MmoWorldView.cs` | MonoBehaviour: `FrameTick` in `Update`, primitives per entity, interpolation, input, token in PlayerPrefs |
| `Assets/SpacetimeDB/module_bindings` | Generated from `templates/server/rust-single` (the TS module is wire-identical) |
| `ci/SessionCheck` | `dotnet run -- http://127.0.0.1:3000 mmo-dev` → `SESSION PASS` |

## Rules (from the official skill and our own runs)

* Call `FrameTick()` every frame on the main thread, or no callbacks fire.
* Register row callbacks once, before the first `FrameTick`, not inside `OnConnect` (that runs again after a reconnect).
* Send intent (`set_input`) only when it changes. The server tick moves you, and you render what it says.
* The PlayerPrefs token *is* the player's identity. It is fine for development. Use OIDC (for example SpacetimeAuth) in production.
* IL2CPP with stripping: add a `link.xml` that preserves `SpacetimeDB` assemblies.
* For big worlds, replace the whole-world subscription with AOI cells (`recipes/aoi-subscriptions.md`).
