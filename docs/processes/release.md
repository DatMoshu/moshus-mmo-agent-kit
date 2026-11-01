# Release

1. Freeze: tag the module source and client builds. Record versions and the module hash. Hash-freeze evidence
   (sha256 of the wasm, bindings and reports) belongs here, at release time only; dev runs do not need it
   (`docs/processes/ops-runners.md`).
2. Gates: `rules/review-gates.md` (all sections), `skills/stdb-security-review`, `skills/stdb-license-check`.
3. Back up production and confirm a restore was rehearsed within 30 days.
4. Publish order: server runtime (if bumped), then module (additive migration only, never `--delete-data`), then
   clients. Old clients must keep working until the new ones roll out, or the module must reject them clearly.
5. Verify on production: two-identity smoke, `tick_health` normal, no reducer errors for 15 minutes.
6. Announce with release notes. Keep the previous module build ready to republish if a rollback is needed.
