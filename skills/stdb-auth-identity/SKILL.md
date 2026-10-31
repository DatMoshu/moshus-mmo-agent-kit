---
name: stdb-auth-identity
description: Wire player identity, login (OIDC issuers such as SpacetimeAuth or a token broker), accounts, admin powers and server-side admission in SpacetimeDB 2.14. Use before any external playtest or when adding login.
---

# Identity, login and admission

## Model

- Every connection has an `Identity` derived from its token. `ctx.sender()` in a reducer is that identity. Clients
  cannot forge it.
- Without a login, the SDK mints an anonymous identity and token. Persist the token per profile to keep the same
  character. Use `one_time_token` style options only for throwaway test clients.
- With a login, an OIDC issuer signs the JWT. Since 2.12, HS256 tokens are rejected; use an issuer that signs RS256 or
  ES256, such as SpacetimeAuth, or a small broker that exchanges a Steam, Google or Firebase login for an RS256 token.

## Accounts

```rust
#[table(accessor = account)]            // private
pub struct Account { #[primary_key] identity: Identity, created_at: Timestamp, banned: bool }

#[table(accessor = player, public)]     // what others may see
pub struct Player { #[primary_key] identity: Identity, #[unique] name: String, online: bool }
```

- Keep provider ids, emails and other secrets in private tables only.
- Create the account on first `client_connected` or on an explicit `join(name)`. The template uses `join` so a
  connection alone does not create rows.

## Admin

- Record the publisher as admin at `init`: `admin: ctx.sender()`. Store it in a table, never in source.
- Every admin reducer starts with `require_admin(ctx)?`.
- To rotate the admin, use an admin-only reducer that writes a new identity. Keep a break-glass procedure in ops docs.

## Admission (private worlds)

```rust
#[reducer(client_connected)]
pub fn on_connect(ctx: &ReducerContext) -> Result<(), String> {
    require_admitted(ctx)        // Err rejects the connection
}
```

- Check admission in `client_connected` **and** at the top of every reducer. Revoking a row does not close a live
  websocket.
- Inter-database callers (2.14 IDC) arrive through `client_connected` with no JWT. Allow-list the sender database
  identities, or their calls retry forever.
- The sidecar's service identity must also be allow-listed and recognised by service-only reducers.

## Checklist

- [ ] No reducer takes an identity argument for authorization (admin targets such as `allow_identity(identity)` are fine behind `require_admin`)
- [ ] Tokens are stored per profile, outside the repo, and never logged
- [ ] Admission is enforced on connect and per reducer
- [ ] Two-identity test: a non-admin calling admin reducers gets `Err`
