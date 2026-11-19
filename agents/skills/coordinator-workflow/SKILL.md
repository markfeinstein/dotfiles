---
name: coordinator-workflow
description: Coordinates bounded Pi workers in visible Rex tabs with owned worktrees, event-driven supervision, checkpoints, and evidence-based acceptance. Use when the primary session delegates or supervises multiple workstreams, not for a small direct task or an assigned child task.
---

# Coordinator Workflow

The primary interactive Pi session is the coordinator, not a dispatcher-only
manager. Keep synthesis, small changes, ambiguous decisions, recovery, and final
acceptance here. Use workers only when independent work or context isolation
justifies the startup, supervision, and review cost.

## Plan and launch

1. Check authority. Standing global authorization permits bounded delegation
   within the user's task, not new credentials, remote mutations, integration,
   activation, deployment, or cleanup. A managed child must not spawn children;
   it reports blockers through `contact_supervisor` instead.
2. Keep a short mission record for multi-workstream work: objective and success
   criteria, authority limits, task dependencies, run IDs, worktree paths and
   owners, decisions, checkpoints, and next actions. Use pi-subagents' existing
   mission/run records rather than another manager process or custom database.
3. Give each worker one bounded contract: objective, inputs, owned paths,
   read-only or writer role, non-goals, acceptance checks, finite deadline, and
   return format (evidence, changed files, commits, risks, remaining actions).
   Follow `repository-workflow` before writes. One writer per checkout; never
   share a writable checkout with the coordinator or another worker.
4. Load `pi-subagents` and preflight the actual worker environment: local Rex
   identity, source/package compatibility, exact model registry ID, project
   trust, required tools/skills, and worker-side permission/guardrail behavior.
   Parent policy is not automatically a worker sandbox. Do not guess a model
   replacement or silently change persistent defaults when an ID is unavailable.
5. Use pi-subagents as the sole managed-worker lifecycle authority. `machine:
   "local"` opens a background Rex tab without taking focus. Herdr wins inside a
   Herdr pane; outside supported terminals, local placement fails closed. Do
   not replace a failed managed launch with a shell-launched Pi or another CLI.
   Report the failure and choose a recovery within existing authority, or ask.
6. Keep at most **three active managed workers across runs** by policy. The
   configured concurrency of three is per run, and two active top-level async
   runs is a separate admission limit—not an aggregate hard cap. Start fewer
   when tasks overlap or the coordinator would have no useful work meanwhile.

## Supervise without polling

- Async completion and supervisor requests wake the coordinator. Return control
  when there is no independent work; do not sleep, poll status, or use `bg_wait`
  for native async subagents. Inspect once when an event, deadline, or concrete
  anomaly makes it useful.
- Liveness is not progress; silence is not failure. Assess changed artifacts,
  completed checks, explicit blockers, and checkpoint freshness against the
  contract. No periodic manager LLM and no inferred failure from a quiet tab.
- Reply to managed children through their native supervisor channel, preserving
  request IDs. Use intercom for peer sessions, not as a second owner of a managed
  run. Bring only genuinely new authority or unresolved decisions to the user.
- On completion, read artifacts and verify the requested observable outcome.
  A successful worker receipt, commit, test exit, or delegation return alone is
  not acceptance. Record evidence and gaps before scheduling dependent work.
- After accepting a worker's result, close its Rex tab unless the user asked to
  keep it.
- For outside systems (CI, Atlantis, review bots), use a bounded watcher such
  as `gh pr checks --watch --fail-fast` or one timed check, not repeated
  `sleep` loops.

## Pause, recovery, and takeover

Distinguish the requested operation before acting:

| Operation | Meaning |
| --- | --- |
| Pause scheduling | Start no new work; existing workers continue. |
| Checkpoint workers | Request evidence, current ownership, pending effects, and next safe action; a request is not a confirmed stop. |
| Interrupt/pause execution | Use supported managed controls and confirm settlement; preserve resumability. |
| Cancel workers | Explicitly stop selected runs; do not assume they can be resumed. |
| Human takeover | Name the exact worker/worktree, checkpoint if possible, stop managed writing and confirm it, then transfer exclusive ownership. |

For a failed connection, distinguish **reattach** (same live process, no task
redispatch), **resume** (new process, original native Pi session), and **replace**
(fresh context plus an explicit checkpoint). Never silently substitute them.
Inspect persisted run/ownership evidence before launching anything. A live or
uncertain writer blocks a replacement writer. If a mutation timed out, inspect
its exact target; never blindly replay it.

Managed local Rex restoration requires the patched package described in the
adoption documentation, the same owning coordinator/workspace, a saved native
session and acknowledged contract, and proof the old Pi writer is gone. The
pinned 0.89.0 baseline alone does not provide this restoration. Keep the native
transcript authoritative; terminal text and bridge summaries are not a session.
Coordinator/server restart recovery and cross-parent adoption are not assumed.

After takeover, the coordinator must not resume until the human explicitly
returns ownership and changes/effects have been reconciled. Keep integration,
activation, and cleanup gated separately even after every worker succeeds.
