# Load test cadence

1. Climb in stages: 10, 50, 100, 200, 500, 1,000 then 5,000 bots (`docs/scale-ladder.md`). Each stage must pass its
   budget before the next one.
2. For each run record the hardware, OS, versions (`stdb.lock`), bot behavior mix and duration, alongside the
   report from `python tools/kit.py loadtest`.
3. Compare against the previous run at the same stage. A regression of more than 20% in tick lateness or updates
   per bot per second needs an explanation before merging.
4. Re-run the current stage after every change to the tick, AOI, hot tables or subscriptions, and after every
   version bump.
5. The bot harness runs on a different machine from the server for any stage above 200, so the bots don't steal CPU
   from the database.
