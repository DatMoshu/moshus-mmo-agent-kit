# Parallel agents (worktree per task)

1. One task = one branch + one git worktree, created outside the main checkout.
2. Each agent runs its own local server on its own port and root directory, with its own database names. Never
   share a dev database between agents.
3. Evidence (logs, reports) goes outside the repo or in a gitignored folder, and only summaries go in the PR.
4. Schema changes are serialized: one agent at a time owns `server/src`. Others rebase and regenerate bindings
   afterwards.
5. Merge through review (`rules/review-gates.md`: at most 3 rounds, only P1/P2 block), then remove the worktree and
   stop its server. Batch P3 nits into one follow-up so a branch never sits open waiting on wording.
