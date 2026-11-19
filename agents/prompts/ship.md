---
description: Integrate the task branch into local main, clean up, and optionally push or rebuild
argument-hint: "[rebuild] [push]"
---
Ship the current task in this repository. Arguments: "${@:-}". Invoking this command is my explicit authorization for the phases below and no others. Report each phase as it completes.

1. Preflight: resolve the repository, worktree, and branch with read-only commands. Confirm the task branch is committed and clean and that its checks pass, using the repository's `AGENTS.md` for the checks and the integration strategy. Stop if anything is uncommitted, failing, or unclear.
2. Integrate: load `repository-workflow` and follow its local integration protocol, using the repository's established strategy, into local `main`. Do not rebase, squash, or force.
3. Verify: rerun the repository's checks on `main` and report each command and its decisive output line.
4. Clean up: remove the task worktree and branch without force, then read back the worktree list and `main`. If this session's working directory is inside the task worktree being removed, run all later commands from the main worktree and tell me to continue in a session started from `main`, because the bash tool fails once its working directory is deleted.
5. Push: do this only if the arguments contain "push". Scan the unpushed commits with the gitleaks command from the repository's `AGENTS.md` and stop on any finding. Then fast-forward push local `main` to `origin/main`, stating the repository, remote, and ref first. Never force-push.
6. Rebuild: do this only if the arguments contain "rebuild". Run the repository's rebuild command from its `AGENTS.md`, in a visible Rex split as the global instructions describe, and report the `Result:` line.

Skip phases 5 and 6 when their word is absent, and say they were skipped. If any phase fails, stop and report the state and the smallest next step.
