---
name: stdb-deploy-selfhost
description: Run a pinned standalone SpacetimeDB server on your own Linux host with TLS, backups, upgrades and monitoring. Use when you go beyond localhost without Maincloud.
---

# Self-hosted deploy (one production instance)

> The SpacetimeDB BSL grant allows **one production instance** and forbids offering it as a database service. Read
> `docs/legal/LICENSING.md`.

## Host

- Linux x86_64, 4+ cores, fast NVMe, and RAM sized to the hot working set. Linux performs better than Windows for the
  server in our measurements.
- Use a dedicated unprivileged user, the server binary at the version in `stdb.lock`, and a data dir on its own
  volume.

## Install pinned

```
curl -sSf https://install.spacetimedb.com | sh     # then:
spacetime version install 2.14.0 && spacetime version use 2.14.0
```

For a fully pinned binary, use the release archive for your platform and a checksum.

## Run as a service

```
spacetime start --listen-addr 127.0.0.1:3000 --data-dir /srv/stdb/data
```

- Use a systemd unit with `Restart=always`, a raised `LimitNOFILE` and the dedicated user.
- Bind to localhost. Terminate TLS in a reverse proxy (Caddy or nginx) that forwards websocket upgrades for `/v1/`.
- Publish from CI or an admin machine: `spacetime publish -s <server> <db> --bin-path <wasm>`. Set up the server alias
  with `spacetime server add`.

## Backups

- Stop or snapshot, then copy the data dir. Keep daily copies for 7 days and weekly for 4.
- Test a restore every month on a second port: start against the copy, run `spacetime sql` row counts and a smoke
  test.

## Upgrades

Use `stdb-upgrade-runtime`: install side by side, copy data, rehearse, server first, keep the rollback.

## Monitoring

- Process up, websocket port reachable, disk free above 20%.
- Module health: poll `tick_health` with `spacetime sql` or a tiny watcher client, and alert at level >= 2.
- Watch logs with `spacetime logs <db> -f` during events.

## Don't

- Expose the server port directly to the internet without TLS.
- Store tokens in the repo or in the systemd unit file. Use the service user's config dir.
- Run multiple production instances without clearing the license first.
