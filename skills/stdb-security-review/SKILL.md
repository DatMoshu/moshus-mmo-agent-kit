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
- [ ] Scheduled reducers check `ctx.sender() == ctx.database_identity()`.
- [ ] IDC receivers allow-list sender database identities.
- [ ] Clients send **intent** (input, target id), never outcomes (new position, damage dealt, item granted).

## Visibility

- [ ] List the `public` tables. Every row of each must be fine for every client, including other players' rows.
- [ ] Per-player data comes through views or `client_visibility_filter` rules, which rely on an index.
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

## Exit

Ship with no open high-severity findings. Medium findings each get an owner and a date.
