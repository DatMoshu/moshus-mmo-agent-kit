# Testing and evidence

Run from the repository root unless a command names a module directory. Record actual output, exact commit, OS, versions, configuration and duration. Keep logs/caches out of commits. [VERIFICATION.md](../VERIFICATION.md) is historical evidence, not an assertion that the current checkout passed.

| Gate | Command | Scope |
|---|---|---|
| Tools | `python tools/kit.py doctor` | Installed tools vs pins; inspect optional engine results |
| Patterns | `python tools/kit.py check` | Known source patterns, not semantic security |
| Kit self-evals | `python evals/run_evals.py` | Rule samples, frontmatter, references; scenarios require judgment |
| Rust build | `cargo build --target wasm32-unknown-unknown --release` in module | Wasm compilation |
| Publish | `python tools/kit.py publish` | Install/update at configured endpoint |
| Codegen | `python tools/kit.py bindings` | Regenerate configured clients; review/commit schema changes |
| Two observers | `python tools/kit.py smoke` | Both SDK identities observe the other's movement |
| Godot observers | `python tools/kit.py smoke --godot` | Movement proof through Godot |
| Load | `python tools/kit.py loadtest --bots 100 --duration 20` | Workload vs [budgets](../../tools/loadtest/budgets.json) |

For module changes run AGENTS.md's definition of done. Add load checks for tick, AOI, or hot tables. Use template-specific tests for tile worlds and handoff: movement smoke cannot validate other schemas. Read [fixture help](../../tools/shard/fixture_game.py) and the [shard contract](../SHARD_CORE.md) before a live tile test.

## Interpret results

PASS, CONCERNS and FAIL are distinct. Low latency with missing clients or observers is not multiplayer proof. Inspect readiness, errors, observed movement, row-update volume, tick health, p95/p99 and duration. A local load result applies to that workload/configuration, not production capacity.

Reconnect tests must reuse an identity and show the fresh input sequence moves it. Test both handoff directions, duplicates, unauthorized calls, and private views when affected. Feature assertions should exercise failure boundaries.

For a denial test, first prove a positive control: the subject exists, the connection works, and the same action is observable when allowed. Then exercise the forbidden action and assert both the explicit refusal and unchanged relevant state over a bounded observation window. A missing subject, disconnected transport, silent timeout, or test that never reached the reducer cannot count as a successful denial. Use synthetic identities/content and avoid importing a consumer project's policy to obtain this general pattern.

## Clean-checkout proof

Run `python tools/quickstart/verify.py` in a disposable clean clone; use `--loadtest` for the optional small diagnostic. The runner records revision, platform, steps, duration and Wasm hash in receipt.json, retains logs, and cleans up its owned server. It does not install the toolchains. It generates bot bindings and node_modules in the source checkout, so inspect its status metadata and retain the fresh-clone provenance. The [Linux CI workflow](../../.github/workflows/verify.yml) uses this path and uploads logs/receipt; workflow source alone is not hosted execution proof.

A candidate needs a new checkout without generated caches/prebuilt artifacts, installation from committed lockfiles, isolated endpoint/config/data, source build, and two observers. Record first-run and warm-run times separately and disclose installation/network exclusions. Clean up only owned processes. Do not wipe valuable databases or stop another developer's server for a port.

KIT_WASM helps diagnose runtime setup but cannot prove local source builds. Platform claims must name the platform actually run. Missing tooling or blocked downloads are skipped/blocked with a reason, never PASS.

## Process and endpoint ownership

An HTTP ping proves that a service answered, not that it belongs to the test.
The quickstart checks listener ownership against its launched process tree on
Windows and Linux before publishing. It fails if ownership cannot be established
or a competing listener occupies the port. Other platforms are unsupported by
this ownership check. A free-port check alone is insufficient because another
process can bind between the check and startup.

Every started verification step has a cleanup scope that also runs when its wait
is interrupted. Regression tests must include a real live child, a competing
listener, and a positive owned-listener control. Mocked exit codes alone cannot
prove process cleanup or endpoint ownership. This protects ordinary local test
isolation; it is not a security boundary against hostile local processes.

## Concurrent client harnesses

Give each client its own user-data directory and output file. Starting two
processes does not prove that they run concurrently: if both write to stdout pipes
but the harness drains only one, the other can block when its pipe fills. This
produced a real false-negative portal/peer test during release preparation.
The shard fixture now writes per-client files and retains complete output with
`--logs <external-directory>`. Require both clients to observe each other; do not
replace that assertion with two independent successful joins.

The fixture rejects nonzero exits, timeouts and script errors even if output also
contains a PASS marker. Mutation checks in a disposable copy can demonstrate that
a focused regression catches the old defect: restore only the faulty behavior,
confirm failure, then restore the fix and rerun. Retain all three results.
