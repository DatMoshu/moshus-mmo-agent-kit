# Review gates

A change merges only when the reviewer can tick every applicable box. "Not run" with a reason is acceptable. "Assumed
passing" is not.

## All changes

- [ ] `python tools/kit.py check`: 0 findings
- [ ] `python evals/run_evals.py`: PASS (when rules, skills, agents or docs changed)
- [ ] No secrets, hosts or private paths in the diff

## Module changes

- [ ] Wasm builds at the pinned version
- [ ] Published to a local dev server, bindings regenerated and committed
- [ ] `python tools/kit.py smoke`: PASS
- [ ] New or changed reducers have a two-identity test (A cannot affect B's rows; non-admin gets `Err` on admin reducers)
- [ ] The schema change is additive, or has a migration plan in `docs/migrations/`
- [ ] Public tables reviewed: every row is safe for every client

## Tick / AOI / hot-table changes

- [ ] `python tools/kit.py loadtest` is not FAIL, and the numbers are compared with the previous report (lateness,
      updates per bot per second, p95)

## Client changes

- [ ] Gameplay code does not import SDK types outside the adapter
- [ ] Smoke test with the client (Godot: `smoke --godot`) or a manual two-client run, noted in the PR

## Releases

- [ ] `skills/stdb-security-review` completed with no open highs
- [ ] `skills/stdb-license-check` completed
- [ ] Backup taken and restore rehearsed within 30 days
