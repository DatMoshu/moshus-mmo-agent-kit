# Milestone with acceptance and stop rules

Every milestone is written down before work starts:

```
Milestone: <name>
Outcome: what a player or owner can do afterwards that they could not do before
Acceptance: the observable checks that prove it (commands, numbers, a recording)
Evidence: where the proof will be stored (docs/VERIFICATION.md, reports/, PR description)
Stop rule: when to stop and ask (for example, two failed approaches, a schema change to cold tables, cost > X)
Rollback: how to undo it
```

1. Break the milestone into tasks that each fit in one session and produce their own evidence.
2. Run the evidence. Paste the numbers, not a summary like "works".
3. Review against the acceptance list. Anything not run is "unverified", never "done".
4. Accept, or write down what is left and why.
