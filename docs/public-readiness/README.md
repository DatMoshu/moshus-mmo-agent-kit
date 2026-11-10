# Release-preparation validation scope

The reproducible minimal gate is [tools/quickstart/verify.py](../../tools/quickstart/verify.py). Run it in a disposable clone with the pinned prerequisites already installed. Its receipt/logs remain external; sanitize paths and credentials before making any evidence public.

## Observed during preparation, 2026-11-10

A fresh Windows checkout at `66df845` completed a Rust 1.97.1 source build for Wasm, locked npm install, fresh TypeScript bot binding generation, typecheck, isolated local publish, two-identity movement smoke, and a 10-bot/five-second diagnostic. The runtime worker's retained receipt recorded PASS in **49.406 seconds**. This measured run excludes toolchain installation and does not establish a universal setup time. A subsequent revision adds richer receipt metadata and requires its own final-candidate run.

Windows source builds need the Visual Studio C++ workload and a developer environment with the Microsoft linker. The initial ordinary-shell attempt exposed Git link.exe shadowing; runner diagnostics now identify that case. Initial npm execution also required inherited PATH normalization. These are prerequisite/environment findings, not engine-client validation.

The authored [Linux CI workflow](../../.github/workflows/verify.yml) has not been executed on hosted GitHub Actions as part of this documentation worker's review. Historical Linux runtime results remain in [VERIFICATION.md](../VERIFICATION.md). Godot, Unity editor, Unreal, macOS, sharded handoff and tile-world behavior are outside this minimal Windows movement-path result. The lead's final candidate report must identify any additional fresh checks and their exact source revision.

## Release review

See [testing](../wiki/Testing.md) for the proof contract, [release maintenance](../wiki/Release-maintenance.md) for publication/wiki preparation, and [dependency inventory](../legal/DEPENDENCIES.md) for license evidence. Documentation and source review do not substitute for runtime qualification. Re-run the gate at the actual release SHA and retain its receipt, logs, tool versions, clean-checkout status, and all skipped checks.
