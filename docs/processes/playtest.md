# Playtest

1. **Fresh world**: a new database name for the playtest. Never reuse a dev database.
2. **Admission**: turn on the allow-list (server-side, in `client_connected` and reducers). Add testers' identities
   or invite codes.
3. **Host**: confirm nobody else needs the machine for the playtest window. Pin the build: record the module hash
   and the client build id.
4. **Publish** the pinned build, then smoke with two identities on the real host.
5. **Invite** testers with join instructions, known issues and how to report bugs.
6. **Monitor** `tick_health` (lateness, level), reducer errors in `spacetime logs`, and player count. Have a written
   threshold for when you pause the test.
7. **Collect feedback** in one place, tagged by build id.
8. **Wind down**: close admission, take a backup, export metrics, then stop or archive the world.
9. **Write up**: what you learned, bugs filed, numbers compared with the last playtest.
