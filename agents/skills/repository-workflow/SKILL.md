---
name: repository-workflow
description: Safely isolate and commit task-owned Git repository changes without disturbing existing work. Use for every repository modification, but not read-only review or remote and deployment actions.
compatibility: Git worktrees on Unix-like systems; local integration requires a clean designated review worktree.
---

# Repository Workflow

Deliver repository modifications as a focused local commit series without
changing unrelated work.

## Scope

Use this skill for file changes in a Git repository, including local commit
planning, verification, and delegated writer handoff. Do not use it for
read-only inspection, remote ref changes, activation, deployment, or destructive
recovery.

A modification request authorizes an isolated local task branch, worktree, and
commit series. Alone, it does not authorize integration or cleanup unless the
repository's `AGENTS.md` grants standing approval for local integration and
cleanup. Push, activation, and deployment always need an explicit request.

## Workflow

1. **Resolve the repository.** Use `git-readonly` to inspect the real top-level,
   Git directory, branch, status, and registered worktrees. In a
   Worktrunk-managed repository, also use `wt -C CONTEXT list --format=json`.
   Record the base commit before mutation; never infer layout from `cwd` or treat
   bare Git metadata as a workspace. Read the target repository's root
   `AGENTS.md` when present: Pi loads it automatically only when the session's
   working directory is inside that repository, and agents often edit a
   repository from a session started elsewhere.
2. **Choose an isolated worktree.** Reuse a clean non-bare worktree only when it
   is uniquely owned and already on the intended delivery branch. Otherwise use
   `git-project worktree --branch BRANCH --base BASE --cwd SOURCE`; omit
   `--base` for an existing branch, and use `--git-dir` for a bare repository
   container. Keep the managed destination unless the repository has an
   established exact layout. Do not substitute raw `git worktree add` when the
   managed command applies.
3. **Preserve existing work.** Never stash, restore, reset, amend, commit, or
   discard changes the task does not own. Keep one writer per checkout.
4. **Plan and seed commits.** Order independently reviewable concerns and choose
   a Conventional Commit subject for each. Create an empty seed commit with
   `--allow-empty` before editing that concern; never deliver an empty seed.
5. **Implement one concern at a time.** Keep its code, tests, documentation, and
   generated artifacts together. Stage exact hunks, or a whole file only when
   every change belongs to the concern, and amend them into the seed. Run focused
   verification before starting another concern.
6. **Fold corrections deliberately.** Amend `HEAD` when it owns the correction.
   For an earlier task-owned unpublished commit, use a targeted `fixup!` commit
   and autosquash once before delivery. Do not rewrite work owned by another
   writer or already published or integrated, except for the isolated candidate
   described below.
7. **Review the completed series.** Inspect every task commit and the full diff
   from the recorded base. In Worktrunk repositories, prefer
   `wt -C SOURCE_WORKTREE step diff TARGET_BRANCH` for the net integration diff.
   Run the smallest final checks that cover changed behavior, broadening only for
   failures or unresolved risk.
8. **Enforce committed completion.** Delivery requires a focused series, no
   temporary seeds or fixups, every task-owned change committed, and a clean task
   worktree. Otherwise report the work as blocked or partial.
9. **Integrate or clean up only when authorized.** Proceed when the user
   explicitly authorizes it or the repository's `AGENTS.md` pre-approves it.
   Before either action, read [Local integration and cleanup](references/local-integration.md)
   and follow its single-owner protocol and exact non-rewriting commands.

A delegated writer stops at a clean, tested, committed source worktree and
reports its path, branch, base, commit range, changed files, checks, and risks.
It does not integrate or clean up unless assigned that exact scope.

## Isolated History-Rewrite Candidates

Only when the user explicitly requests a history-rewrite candidate, a new
task-owned branch and worktree may rewrite copies of published or integrated
commits. Record the original tip before starting; do not move or rewrite any
pre-existing branch, tag, or remote ref, or alter another writer's worktree.
Before presenting the candidate, verify that its final Git tree is identical to
the recorded original tip and report the old and new commit counts and any
verification failures. A candidate does not authorize replacing an existing
branch, integration, cleanup, publication, or force-pushing.

## Safety Boundaries

- Never force-push, hard-reset, run destructive `git clean`, recursively remove
  broad paths, force-delete branches, or pass Worktrunk force flags.
- Local commit authorization does not authorize fetch, push, remote deletion,
  integration, activation, deployment, or cleanup.
- Never put realistic-looking credentials (webhook URLs, tokens, keys,
  connection strings) in tests, fixtures, or docs, even fake ones. Use
  `example.com` hosts and obviously fake values such as `EXAMPLE_TOKEN`; secret
  scanners block pushes on realistic formats.
- Stop when repository ownership or the base is ambiguous, isolation fails,
  unrelated changes cannot be preserved, verification fails without a coherent
  authorized commit, integration conflicts, or cleanup ownership is uncertain.

## Output

Report the reached state, repository and worktree, branch and commit range,
changed files, verification, clean-worktree status, residual risks, and exact
next action.
