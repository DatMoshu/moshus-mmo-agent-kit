# unreal: thin Unreal Engine client starter

**Status: UNVERIFIED (not compiled).** No Unreal Engine was available while building the kit. What
*was* checked: the bindings in `Source/MmoKitClient/{Public,Private}/ModuleBindings` were generated
by `spacetime generate --lang unrealcpp` 2.14.0 from `templates/server/rust-single`. Every SDK and
binding symbol used by `MmoGameManager` (`UDbConnection::Builder`, `WithToken`, `OnConnectError`,
`FOnConnectErrorDelegate`, `UCredentials`, `BIND_DELEGATE_SAFE`, `FrameTick`, `IsActive`,
`Db->EntityTransform->OnInsert/OnUpdate/OnDelete`, `Reducers->Join/SetInput`, `FSpacetimeDBIdentity::ToHex`)
was matched by hand against the generated headers and the SDK headers at tag `v2.14.0`. The first
person to build it should record the result in `docs/VERIFICATION.md`.

Based on the official `unreal` skill (`skills/vendor/official/unreal`).

## Use it

1. Get the SDK plugin at the version pinned in `stdb.lock`: copy `sdks/unreal/src/SpacetimeDbSdk`
   from the SpacetimeDB repo at tag `v2.14.0` into `Plugins/SpacetimeDbSdk/` (it is git-ignored here).
2. Open `MmoKitClient.uproject` (set `EngineAssociation` to your engine version), then let it build.
   On Windows you need Visual Studio with the C++ game workload.
3. Place an **MmoGameManager** actor in your level. Set `ServerUri` (`127.0.0.1:3000`), `DatabaseName`, and
   optionally `EntityClass` (a Blueprint with a mesh).
4. Play and move with WASD. Run the Godot client, the web admin or the bots next to it to see other players.

Regenerate the bindings whenever the module changes:

```bash
spacetime generate --lang unrealcpp --uproject-dir . --module-path <kit>/templates/server/rust-single --unreal-module-name MmoKitClient
```

The generator also writes `Source/MmoKitClient/MmoKitClient.{h,cpp}` (the primary game module) if they are missing.

## Rules

* Call `Conn->FrameTick()` every frame (done in `Tick`), or `Conn->SetAutoTicking(true)` once. Pick one.
* Bind row delegates once, right after `Build()`. Every handler must be a `UFUNCTION()`.
* The world is in metres. Unreal uses centimetres (`UnitsPerWorldUnit = 100`).
* Send intent only when it changes. The server tick is authoritative.
* `UCredentials` stores the token in a file. That token is the player's identity, so treat it as a secret.
  It is fine for development; use OIDC in production.
* Big worlds: replace the whole-world subscription with AOI cells (`recipes/aoi-subscriptions.md`).
