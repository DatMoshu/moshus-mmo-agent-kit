---
name: stdb-deploy-maincloud
description: Publish a SpacetimeDB module to Maincloud (Clockwork Labs' hosted service) and point clients at it. Use for zero-ops hosting or when the self-host license limits matter.
---

# Maincloud deploy

## When

- You want zero ops, or more than one production world without self-host license questions.
- Your scale and budget fit Maincloud's current pricing. Check the official site; the kit does not quote prices.

## Steps

1. Log in: `spacetime login`. Your token stays in your CLI config; never copy it into the repo.
2. Publish: `spacetime publish -s maincloud <db-name> --module-path server`, or `--bin-path` with a prebuilt wasm.
   Database names are global on Maincloud, so pick a unique, lowercase, dashed name.
3. Clients: set the URI to `https://maincloud.spacetimedb.com` and the database name. Keep these in a client config
   file per environment, not hard-coded.
4. Regenerate bindings from the same module version (`python tools/kit.py bindings`).
5. Smoke test against Maincloud with two fresh identities. Then run a short load test at low bot counts. Don't
   load-test a shared service at full scale without permission.

## Environments

| Env | Database | Who publishes |
|---|---|---|
| dev | local `mmo-dev` | anyone |
| staging | `<game>-staging` on Maincloud | CI or lead |
| prod | `<game>` on Maincloud | release owner only |

## Gotchas

- `--delete-data` on Maincloud destroys a live world. Never use it on prod.
- Destructive schema changes need the `stdb-migration` dual-table approach, just like self-host.
- Keep the identity that published prod (the owner) safe. Losing it means losing control of the database.
