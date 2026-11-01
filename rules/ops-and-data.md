# Ops and data rules

- O1. **Versions move together** (CLI, server, crate, SDKs, Godot SDK), recorded in `stdb.lock`. Follow
  `docs/processes/version-bump.md`.
- O2. **Never `--delete-data` on a world with players.** Destructive schema changes use the dual-table migration in
  `skills/stdb-migration`.
- O3. **Rehearse on a copy.** Upgrades, migrations and restores are run first on a copied data dir with a second server
  on another port.
- O4. **Backups are tested** by restoring them at least monthly.
- O5. **Server first, modules second** when the runtime changes (2.14 changed `is_internal` semantics).
- O6. **No secrets in git:** tokens, keys, `.env`, server hostnames and IPs, SSH config. Use environment variables or
  untracked files.
- O7. **One production instance per BSL grant** unless you have a commercial license or use Maincloud
  (`docs/legal/LICENSING.md`).
- O8. **Load test before every public playtest** and after every change to the tick, AOI or hot tables. Keep the
  reports.
- O9. **Record verification** honestly in `docs/VERIFICATION.md`: what ran, where, which version, the result. Never
  mark something verified that was not run.
- O10. **Runners are re-runnable.** Ops scripts are idempotent, retry only transient failures with backoff, read
  JSON with `utf-8-sig`, and keep hash-freeze evidence for releases (`docs/processes/ops-runners.md`).
