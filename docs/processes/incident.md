# Incident response

1. **Look**: `tick_health` (lateness and level), player count, error rate in `spacetime logs <db>`.
2. **Find the hot spot**: which reducer is slow or failing, which subscription fans out (a crowd in one cell, an
   unindexed filter, a public table that grew), or a sidecar retry storm.
3. **Stabilize** before fixing: close admission, disable the feature with a config-table flag, raise the tick
   interval, or have the sidecar back off. Don't wipe data.
4. **Hotfix** with an additive module publish only, after `check`, build and smoke on a local copy.
5. **Confirm** recovery in the metrics for at least 15 minutes.
6. **Postmortem** within a few days: timeline, cause, what detected it, what will stop it recurring (a rule in
   `rules/`, a check, a load test scenario), and an ADR if the design changes.
