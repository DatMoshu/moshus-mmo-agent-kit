# Ops runners: idempotent, retryable, BOM-safe

An ops runner is any script or agent loop that does real work against a server: publish, bindings, smoke, load
test, backup, restore drill, migration batch, deploy. Runners fail in boring ways (a dropped connection, a server still
starting, a file written by another tool). Make those failures cheap: re-running the same command must be safe and
should finish the job.

Field lessons behind this page, generalized:

* A hosted run failed halfway. Nobody could tell which steps had finished, so it needed a manual reconciliation and
  several source fixes before a rerun.
* A rerun reused a bound (a row count or id range) computed by the failed attempt, and checked the wrong range.
* A receipt JSON written on Windows had a UTF-8 BOM, and the next step's JSON parser rejected it.
* Freezing hashes of every artifact on every dev run cost more time than the runs themselves.

## Rules

1. **Idempotent steps.** Each step either checks whether its result already exists and skips, or produces the
   same end state when run twice. Examples: re-publishing the same module, `ensure_*` seed reducers, migration batches
   that skip ids already copied, request ids for HTTP-triggered reducers (`recipes/idempotent-requests.md`).
2. **Receipts per step.** Write a small JSON receipt after each step (step name, inputs, versions, result, report
   path, time). A rerun reads the receipts and resumes after the last good step instead of reconciling by hand.
3. **Recompute bounds every attempt.** Row counts, id ranges, timestamps and "expected" numbers are derived fresh at
   the start of each attempt. Never carry them over from a failed attempt.
4. **Retry transient failures only, with backoff.** Retry connection refused or reset, timeouts, DNS blips, and HTTP
   429/502/503/504, up to 2-3 times with exponential backoff and jitter (2 s, 4 s, 8 s x 0.5-1.0). Do **not** retry:
   a FAIL verdict, a compile error, a publish refused for a schema change, auth errors (401/403) or 404s. Those are
   real results and need a human or a fix.
5. **Ping before work.** Wait for `GET /v1/ping` to answer (with retries) before smoke or load runs, so a server that
   is still starting is not reported as a failed test.
6. **BOM-tolerant JSON.** Read every JSON input, receipt and report with `utf-8-sig` (Python) or strip a leading
   `\ufeff` before parsing (other languages). Write JSON as UTF-8 **without** a BOM. Windows PowerShell 5.1
   `Set-Content -Encoding utf8` and `Out-File -Encoding utf8` add a BOM. Use `[IO.File]::WriteAllText($path, $json)`,
   or `-Encoding utf8NoBOM` on PowerShell 7.
7. **Evidence sized to the stakes.**
   * Dev and CI runs record the command, the pinned version, the verdict and the report path. That is enough.
   * Heavy hash-freeze evidence (sha256 manifests of the wasm, bindings, data dir and reports, signed or committed)
     is for **releases only** (`docs/processes/release.md`).
8. **Say what happened.** On final failure, print which step failed, whether it was transient, how many attempts
   were made, and the exact command to resume.

## What `tools/kit.py` does

| Runner | Behaviour |
|---|---|
| `publish` | Re-publishing the same module is idempotent. A failed publish whose output looks transient (connection refused/reset, timeout, 502/503/504) is retried. A publish refused for a schema change is not retried. |
| `smoke`, `loadtest` | Ping `/v1/ping` first (with retries). Re-run the bot harness only when it produced no verdict at all. A FAIL verdict is final. Bots use fresh identities, so reruns are safe. |
| `bindings`, `vendor-skills` | HTTP fetches retry on connection errors and 429/502/503/504, never on 404. |
| `check`, `kb-export`, `loadtest` budgets, `stdb.lock` | Read with `utf-8-sig`, so a BOM is harmless. |

Tune with `KIT_RETRIES` (default 2, `0` disables) and `KIT_RETRY_BASE` (first delay in seconds, default 2).
