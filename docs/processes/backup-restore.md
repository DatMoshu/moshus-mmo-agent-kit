# Backup and restore drill

1. Stop the server, or use a filesystem snapshot that is consistent (snapshot the whole data directory at once).
2. Copy the data directory (commit log and snapshots) to storage on another machine.
3. Restore: on another port and root directory, start the **same server binary version** against the copy.
4. Verify: row counts of key tables match, two existing identities can log in with saved tokens, and the tick runs.
5. Time it. Write the date, duration and result into `docs/VERIFICATION.md`.
6. Do this monthly and before every release and version bump.
