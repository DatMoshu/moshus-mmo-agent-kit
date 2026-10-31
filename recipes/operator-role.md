# Operator role (sidecars and GM tools without the publisher token)

**Problem.** The starter's admin is the identity that published the module. Do not hand that token to a sidecar,
a GM web tool or a teammate: it can also republish and delete the database. Give each helper **its own identity**
and an explicit role instead.

Code: [`snippets/operator.rs`](snippets/operator.rs).

1. Append the snippet. In reducers that operators may call (e.g. `set_admission_open`, `allow_identity`, moderation),
   replace `require_admin(ctx)?` with `require_operator(ctx)?`. Keep `grant_operator`, schema-sensitive reducers and
   anything destructive on `require_admin`.
2. Start the helper once with a token file so its identity is stable:
   `npx tsx src/main.ts --uri ws://127.0.0.1:3000 --db my-mmo --token-file .sidecar/token --once`
   It prints `sidecar connected as <hex>`. Keep the token out of git. The sidecar `.gitignore` ignores `.sidecar/`, and the repo ignores `*.token`. A path outside the repo is better still.
3. As the admin, run: `spacetime call my-mmo grant_operator 0x<hex> '"ops"'`.
4. From now on, run the helper with the same `--token-file`.

**Checked (2026-10-31, local 2.14):** Ran the sidecar with `--guard --every 1 --red-level 0 --red-ticks 1`, which forces a close.
* Before the grant: `set_admission_open failed: SenderError: operator only`.
* After the grant: `guard: tick red for 1 checks; admission closed`, and `world_config.admission_open = false`.

**Roles.** `role` is a free-form string. If GMs and automated helpers need different powers, check it
(`require_role(ctx, "gm")`). Audit-log grants: the snippet already logs them with `log::info!`, and `spacetime logs` shows them.
