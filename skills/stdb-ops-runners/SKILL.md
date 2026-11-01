---
name: stdb-ops-runners
description: Write or fix ops runners (publish, smoke, load test, backup, migration batches, deploy scripts) so they are idempotent, retry only transient failures with backoff, resume from receipts and read JSON with a BOM safely. Use when a scripted run against a SpacetimeDB server fails halfway, flakes, or needs a rerun.
---

# Retryable ops runners

The full rules and the rationale are in `docs/processes/ops-runners.md`. `tools/kit.py` follows them, so copy its
`retry`, `read_json` and `wait_for_server` helpers when you write a new runner.

## Checklist

- [ ] Every step is idempotent: it skips when its result already exists, or running it twice leaves the same state.
- [ ] Each step writes a JSON receipt (step, inputs, versions, result, report path). Reruns resume after the last good
      step.
- [ ] Bounds (row counts, id ranges, expected totals) are recomputed at the start of every attempt.
- [ ] Only transient failures are retried: connection refused/reset, timeouts, DNS, HTTP 429/502/503/504. Use 2-3
      retries with exponential backoff and jitter.
- [ ] A FAIL verdict, compile error, refused schema change, 401/403 or 404 is reported, never retried.
- [ ] The runner pings `GET /v1/ping` before smoke or load work.
- [ ] JSON is read with `encoding="utf-8-sig"` (or a leading `\ufeff` is stripped) and written without a BOM.
- [ ] Hash-freeze evidence (sha256 manifests of artifacts) only for releases. Dev runs record command, version,
      verdict and report path.
- [ ] On the final failure the runner prints the failed step, the attempt count and the resume command.

## Wrong vs right

```python
# Wrong: breaks on a receipt written by Windows PowerShell 5.1 (UTF-8 with BOM)
receipt = json.loads(Path("receipt.json").read_text(encoding="utf-8"))

# Right
receipt = json.loads(Path("receipt.json").read_text(encoding="utf-8-sig"))
```

```python
# Wrong: retries everything, including a real FAIL, and hammers the server
while subprocess.run(cmd).returncode != 0:
    pass

# Right: retry only transient failures, with backoff (see tools/kit.py `retry`)
result = retry("publish", publish_once)   # publish_once raises Transient on a connection error
```

```powershell
# Wrong (Windows PowerShell 5.1): writes a BOM
$json | Set-Content -Encoding utf8 receipt.json
# Right
[IO.File]::WriteAllText("$PWD\receipt.json", $json)
```

## Migration batches

Scheduled migration reducers are runners too: copy a bounded batch per run and skip ids already copied, so a crash
or a republish in the middle is harmless (`skills/stdb-migration`).
