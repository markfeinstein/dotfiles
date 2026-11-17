# Pi coordinator and visible Rex workers

## Intended workflow

The primary interactive Pi session does most reasoning, synthesis, and small
changes. It delegates bounded independent work only when parallelism or context
isolation pays for the overhead. Standing authorization in
`agents/global-instructions.md` permits that choice; it does not grant new
side-effect authority. Managed children cannot delegate further.

`coordinator-workflow` supplies the multi-workstream procedure. pi-subagents owns
managed worker lifecycle, missions, supervisor requests, artifacts, and results.
Intercom remains for peer sessions. Rex supplies visible background tabs, not a
second scheduler. There is no periodic manager LLM or automatic mutation replay.

Six existing native roles default to `machine = "local"`: scout, researcher,
evidence-auditor, worker, reviewer, and oracle. Their model choices are unchanged.
Inside Rex, local placement opens a background tab; inside Herdr, Herdr takes
precedence. Outside those supported terminals, launch fails closed. Writers need
pre-created isolated worktrees: placed workers do not support pi-subagents'
automatic managed-worktree option.

### Limits and safety

- Policy: at most **three active managed workers across runs**.
- `globalConcurrencyLimit = 3`: a **per-run** scheduling limit, not a fleet cap.
- `maxActiveAsyncRunsPerSession = 2`: top-level async admission, not total workers.
- `maxSubagentDepth = 1`: no grandchildren by default.
- Existing one-hour timeout, five-minute pre-deadline checkpoint, active-run
  prompt, and spawn ceilings remain. A checkpoint request is not proof of a stop.
- Parent instructions and guardrails are not a sandbox. Placed launches have
  their own resource and tool restrictions; verify worker-side gates in the
  actual environment before giving a writer consequential work.
- Pausing scheduling, requesting checkpoints, interrupting execution, and
  cancelling runs are distinct. Human takeover requires confirmed exclusive
  ownership; restarting afterward requires explicit hand-back and reconciliation.

## Worker tab labels

Generated `subagent-<8 hex digits>` labels become
`Agent · <project> · <branch> · <run suffix>`. The per-window state stores the
suffix so branch changes and subsequent label-hook processes keep both the
worker marker and identity. Long labels reserve room for the suffix within the
128-character limit. Human-renamed labels are left alone. Old three-column
state preserves the Agent marker but cannot recover an ID already lost.

`python3 nix/tests/rex-label-window.py` exercises the real shell script using
strict mock Rex/Git executables, including reloads, custom labels, legacy state,
and long names. `checks.aarch64-darwin.rex-worker-labels` runs it under Nix. These
are mocked integration checks, not confirmation of live title hooks; they never
rename operator tabs.

## Configuration surface

Profiles can merge runtime settings without replacing the generated file:

```nix
dotfiles.pi.subagentConfig = {
  globalConcurrencyLimit = 1;
  maxActiveAsyncRunsPerSession = 1;
};
```

The single package slot defaults to `npm:pi-subagents@0.89.0`. A later authorized
adoption can replace it with a patched local package:

```nix
dotfiles.pi.subagentPackageSpec = "/absolute/path/to/pi-subagents-task-worktree";
```

Do **not** add the patched package to `packageSpecs` as a second copy. Both parent
and worker must load the same source. A local path is host-specific and must be
kept present; for durable distribution, review and publish a pinned package in a
separately authorized step.

## Restoration scope and rollout

The companion pi-subagents branch `feat/rex-worker-restore` adds ownership-checked
native session reopening for local Rex. Its initial source commit is `2a77bb6a`.
The default published 0.89.0 package does **not** include that patch.

The patch keeps canonical Pi JSONL history, parent/workspace/contract identity,
and an exclusive runner-plus-Pi writer lease. It restores into a new background
tab using the existing resume action only after the old Pi writer is gone. An
idle retained Pi still counts as a writer. It refuses arbitrary transcripts,
foreign parents, missing ownership evidence, and changed launch contracts.

It does not provide automatic coordinator/server restart recovery, cross-parent
adoption, or a general workflow-child restore guarantee. Explicitly cancelled
runs retain the existing non-resumable semantics; use supported pause/interrupt
controls when continuation is intended. Never reopen a managed transcript by
hand or delete its lease while managed ownership exists.

### Adoption checklist — not executed by these source changes

1. Review and explicitly authorize local integration of the source branches.
   The work-profile repository's locked shared-dotfiles input still needs a
   separately authorized update; changing this shared source does not update
   that pin. Preserve other sessions' work and use the integration-lane protocol.
2. Choose the patched package source through `subagentPackageSpec`, if restoring
   workers is wanted. Check parent and child load exactly one matching copy.
3. Preflight exact configured model IDs against the active registry. During
   development, `github-copilot/gpt-6.1-terra` was unavailable while the explicitly
   chosen `openai/gpt-6.1-terra` launch override was accepted. This is evidence of
   environment drift, **not** a persistent replacement recommendation.
4. Obtain explicit authorization before package installation/update, activation,
   or restarting sessions. These commits perform none of them. Existing running
   sessions continue with their original tools and instructions.
5. In a disposable fixture, verify project trust, package loading, model access,
   actual child tool/permission gates, background tab labeling, and native
   supervisor replies. A development worker failed before bridge startup;
   the production cause remains undiagnosed. Do not bypass prompts with a broad
   approval flag or assume the restore patch fixes that failure.
6. Exercise one authorized low-risk task through the real coordinator tool:
   launch, checkpoint/interrupt, confirm writer closure, resume, verify native
   context, and confirm only one final result is accepted. Keep the fixture's
   worktree unchanged by other writers. Only then scale out.

Rollback is a separately authorized configuration/activation change: return the
single package slot to the pinned release and restore prior settings if needed.
Do not roll back while workers are active or discard their transcripts/worktrees.

## Verification and evidence boundaries

- `python3 nix/tests/pi-coordinator-structure.py` checks skill shape, fixture
  structure, and safety text. It is not a behavioral evaluation.
- `nix build --offline --no-link .#checks.aarch64-darwin.pi-coordinator` evaluates
  defaults/profile overrides, preserved models, package substitution, skill
  installation/exclusion, and runs the structural checks. It does not activate.
- `agents/skills/coordinator-workflow/evals/` contains unexecuted routing and
  behavior scenarios plus a matched-baseline evaluation plan. No skill efficacy
  or live model-compliance improvement is claimed.
- The companion source has passing unit/integration suites and a real-Pi/private-
  Rex restoration smoke test with a local deterministic model endpoint. That
  smoke verifies native history/context preservation, duplicate-writer refusal,
  and process closure, not production auth, guardrails, reasoning, or the full
  interactive coordinator resume path.

No additional orchestration plugin is installed. pi-sessions keeps search,
recall, and titles; its overlapping messaging/subagent/handoff features remain
disabled. No push, integration, activation, live package edit, or existing-tab
rename is performed by these source-only changes.
