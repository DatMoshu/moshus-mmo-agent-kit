---
name: stdb-security-review
description: Audit a SpacetimeDB module and its clients for authority, visibility, input validation, abuse and secret handling before playtests and releases. Use before any external exposure.
---

# Security review

Run `python tools/kit.py check` first. Then go through the list. Record findings with severity and a fix in
`docs/security-review-<date>.md`.

## Authority

- [ ] Every reducer derives the actor from `ctx.sender()`. No identity or player-id arguments are used for authorization.
- [ ] Admin reducers call `require_admin` first. Service reducers call `require_service` first.
- [ ] No reducer that any client can call can end every session, reset the world or trigger a module update (R31).
- [ ] Scheduled reducers check `ctx.sender() == ctx.database_identity()`.
- [ ] IDC receivers allow-list sender database identities.
- [ ] Clients send **intent** (input, target id), never outcomes (new position, damage dealt, item granted).

## Visibility

- [ ] List the `public` tables. Every row of each must be fine for every client, including other players' rows.
- [ ] Per-player data comes through private tables plus `#[view]`s, which rely on an index. Treat
      `client_visibility_filter` (RLS) as a last resort: in 2.14.0 it needs the `unstable` crate feature, refuses nested
      `IN (SELECT ...)`, and a JOIN-based filter breaks client JOIN subscriptions on that table (R30).
- [ ] No secrets (emails, provider ids, IPs, tokens, admin notes) in public tables or event payloads.

## Inputs

- [ ] Strings are bounded and charset-checked. Floats are `is_finite()`. Enums and directions are clamped.
- [ ] Collections in arguments are length-capped.
- [ ] Per-identity rate limits exist on chat, crafting, trading and any reducer that writes rows.

## Abuse

- [ ] Row growth per identity is capped (inventory slots, messages, buildings).
- [ ] Anonymous identities are cheap, so rate-limit sign-up flows and consider admission or allow-lists for alphas.
- [ ] Economy actions go through server-side escrow, never two client calls.
- [ ] HTTP-triggered reducers are idempotent (request ids).

## Secrets and ops

- [ ] No tokens, keys, `.env` files or server addresses in the repo (`git grep -nI -E "token|secret|BEGIN .*PRIVATE"`).
- [ ] Bindings and logs don't print tokens.
- [ ] Hosted servers expose only HTTPS/WSS behind a reverse proxy. The admin path is not public.
- [ ] A backup restore was rehearsed in the last month.

## Severity and rounds

Tag findings with the severities in `rules/review-gates.md`: **P1** (authority hole, leak, data loss, secret),
**P2** (real defect or a missing required check), **P3** (docs, wording and evidence nits). List every finding in the
first pass. Re-review checks only the P1/P2 fixes, and the review ends after 3 rounds at most. P3 items are batched
into one follow-up and never block a merge or a playtest.

## Exit

Ship with no open P1 findings. P2 findings are fixed or each get an owner and a date before external exposure. P3
findings go in the batched follow-up.
