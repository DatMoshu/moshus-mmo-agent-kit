# Review gates

A change merges only when the reviewer can tick every applicable box. "Not run" with a reason is acceptable. "Assumed
passing" is not.

## Review rounds (cap: 3)

Reviews are short and bounded. Long review loops cost more than the bugs they catch: one field project spent 14
review rounds over about 7 hours on a change that never merged, while leads working with light review shipped about
11 commits each in under 2 hours.

**Severity.** The reviewer tags every finding:

| Tag | Meaning | Blocks merge? |
|---|---|---|
| **P1** | Wrong or unsafe: authority hole, data loss, a destructive migration, a secret in the diff, a broken build, a failing gate below | yes |
| **P2** | A real defect in behaviour or a missing required check for this change type (for example no two-identity test for a new reducer) | yes |
| **P3** | Nits: wording, docs, evidence formatting, naming, style, "could also test X", extra screenshots | **never** |

**Rounds.**

1. **Round 1:** one complete pass. List *every* finding at once with its tag. Do not drip-feed new findings in later
   rounds unless the fix itself introduced them.
2. **Round 2:** check only the P1/P2 fixes. If they are fixed, approve.
3. **Round 3 (last):** only if a P1/P2 fix is still wrong. After round 3 the lead decides: merge with the remaining
   issue split into its own task, or drop or split the change. There is no round 4.

**P3 nits** go into **one** batched follow-up (one issue, task or commit after merge). They never block a merge and
never reset the round count. "Evidence could be more detailed" is P3 unless a required check was not run at all
(that is P2).

Approval means "no open P1/P2", not "nothing left to improve".

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
