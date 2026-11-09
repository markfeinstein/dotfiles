# Local Integration and Cleanup

Read this reference only when the user explicitly authorizes local branch
integration or task-worktree cleanup.

## Claim the Integration Lane

Before mutation:

1. Inspect live same-repository sessions with intercom when available.
2. Coordinate with any session currently responsible for the target branch or
   worktree. Only one session may own integration into that target.
3. Batch the read-only preflight: verify exact source and target paths and
   branches, source tests and cleanliness, target cleanliness, commits,
   ancestry, and the complete diff.
4. Use `wt -C SOURCE_WORKTREE list --format=json` for consolidated Worktrunk
   state and `git-readonly` for exact ancestry or commit inspection.

If ownership, paths, cleanliness, verification, or ancestry is uncertain, stop
before integration.

## Integrate Without Rewriting

When the target is an ancestor of the clean source, prefer:

```sh
wt -C SOURCE_WORKTREE step push --format=json TARGET_BRANCH
```

Despite its name, `wt step push` advances only the local target branch and
worktree. It does not contact a remote, has no force mode, and rejects a
non-fast-forward target. Add `--no-ff` only when the repository's established
local strategy requires a merge commit.

When repository-defined pre-merge hooks require a merge operation, use exactly:

```sh
wt -C SOURCE_WORKTREE merge --no-commit --no-rebase --no-remove --format=json TARGET_BRANCH
```

This preserves the reviewed commit graph and leaves the source branch and
worktree intact. Never run bare `wt merge` or allow default staging, squashing,
rebasing, or cleanup behavior.

If the target is not an ancestor, a merge conflicts, or the normal strategy
needs another topology, stop rather than automatically rebasing or squashing.
Use a different non-destructive strategy only when it is explicitly authorized
and established for the repository.

Keep the integration mutation in its own call. Report successful local branch
integration immediately, before post-integration verification or any cleanup.

## Verify and Clean Up

Run appropriate target-worktree checks after integration. Treat tests,
publishing, activation, deployment, and cleanup as separate phases and do not
include their elapsed time in the integration result.

Cleanup requires separate authorization and certain ownership. Confirm with
`wt list --format=json` that the exact source is integrated or empty, then use:

```sh
wt -C TARGET_WORKTREE remove --foreground --format=json SOURCE_WORKTREE
```

Never pass `--force` or `--force-delete`. If Worktrunk refuses removal, stop and
report the reason. After removal, read back the Worktrunk list and target branch
before reporting cleanup complete.

## Operational Efficiency

- Treat straightforward integration as one operation; do not create a todo list
  merely to mirror preflight, integration, verification, and cleanup commands.
- Use phase-specific statuses such as `verifying merge readiness`, `merging
  branch`, `verifying merged result`, and `cleaning merged worktree`. Report
  `waiting` or `blocked` while another owner or approval gate prevents progress.
- When visible context usage is at least 50%, stop at the clean committed source
  boundary and recommend `/compact` or `/clone` before integration or cleanup.
