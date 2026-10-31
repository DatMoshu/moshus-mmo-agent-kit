# Client rules (Godot, Unity, Unreal, web, bots, sidecars)

- C1. **One SDK adapter.** Exactly one module or class per client talks to the SpacetimeDB SDK (Godot `Net`, a Unity
  `SpacetimeManager`, an Unreal connection actor, a web `connection.ts`). Gameplay code never imports SDK types
  directly.
- C2. **Intent only.** Clients call reducers with inputs and requests. They never write outcomes (positions, damage,
  inventory).
- C3. **Bindings are generated.** Never edit them. Regenerate after every schema change (`python tools/kit.py
  bindings`) and commit them for engine clients.
- C4. **Tokens.** Persist per profile in user storage (PlayerPrefs, `user://`, `Saved/`, localStorage). Never log
  them or commit them. Test clients may use throwaway identities.
- C5. **Subscriptions are scoped.** Subscribe to your own rows, then per-cell AOI queries, then small global tables.
  No `SELECT *` on hot tables.
- C6. **Cache reads are filtered** by the current cell set (some SDKs keep stale rows after unsubscribing).
- C7. **Pump the SDK.** Unity, Unreal and C# clients call `FrameTick()` every frame on the main thread.
- C8. **Reconnect safely.** Register callbacks once. Treat reducer calls lost in a disconnect as unknown outcomes.
  Don't auto-retry non-idempotent calls.
- C9. **Smooth, don't trust.** Predict your own avatar, reconcile to the server, and interpolate others 100-150 ms
  behind.
- C10. **Testable headless.** Each client has an autopilot or bot mode so `kit.py smoke` and load tests can drive it
  without a human.
- C11. **Sidecars** use their own service identity, call only service reducers and never decide game rules.
