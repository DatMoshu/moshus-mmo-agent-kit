# Invite-only playtest

The starter module ships with admission control. Here is how to run a closed test with it.

| Step | Command (local CLI; add `-s <server>` for a remote host) |
|---|---|
| Close the world | `spacetime call my-mmo set_admission_open false` |
| Tester connects once and sends you their identity (shown in the client or web admin) | |
| Admit them | `spacetime call my-mmo allow_identity 0x<identity>` |
| Remove someone | `spacetime call my-mmo revoke_identity 0x<identity>` (also zeroes their input) |
| Open to everyone | `spacetime call my-mmo set_admission_open true` |

`require_admitted` passes if admission is open, the caller is the admin, or the caller is on the allowlist. Every
gameplay reducer (`join`, `set_input`, plus your own) should call it first.

Tips:

* Give testers a build that keeps its token (the Godot/Unity/web templates already persist it), or their identity changes
  every launch and the allowlist won't match.
* Let a GM or helper manage the list without the publisher token: switch `allow_identity`/`revoke_identity` to `require_operator`
  (`operator-role.md`).
* Hosting checklist before inviting anyone: `docs/processes/playtest.md` and `backup-restore.md`. Also consider the sidecar guard (`templates/sidecar --guard`), which closes admission when the tick runs red.
* Keep invite codes, tester lists and server addresses out of the repo. Pass them to testers directly.

**Status:** the reducers are part of the verified starter (smoke test). This page adds no new code.
