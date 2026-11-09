# AGENTS

## Environment

- Git layouts vary. Resolve the real top-level, Git directory, branch, and
  registered worktrees instead of inferring them from the current path. Treat
  bare Git directories as infrastructure, not workspaces.

## Credentials and External Systems

- Inspect non-secret metadata and effective configuration before credential use.
  Prefer configured host aliases, on-disk identity files, and existing local
  credential mechanisms.
- Use existing `pass` entries before `op`. Do not infer local lookup order from a
  repository's runtime secret source. Use 1Password only when the local entry is
  absent, unusable, stale, or the task explicitly manages 1Password; network or
  route failures do not justify that fallback.
- Never reveal credential values. Validate that required values are nonempty
  before consequential actions while keeping them out of chat, logs, tracked
  files, shell history, and transcripts.

## Delivery and Preservation

- Before modifying a Git repository, load and follow `repository-workflow` for
  isolation, commit organization, local integration, verification, and cleanup.
- Preserve unrelated and pre-existing work. Never discard it, force-push,
  hard-reset, run destructive `git clean`, force-delete branches, pass force
  flags to Worktrunk, or recursively remove broad paths.
- Local modification authorization does not authorize integration, push,
  activation, deployment, runtime changes, or cleanup. Follow the skill's
  single-owner integration-lane protocol whenever those actions are requested.

## Command Boundaries

- Keep read-only inspection, local mutation, remote or credential access, and
  destructive or privileged operations in separate calls when their authority
  or failure handling differs.
- Use `git-readonly` for Git inspection, including the first check of the real
  repository root and branch. In Worktrunk-managed repositories, use
  `wt list --format=json` for consolidated worktree and branch state. Reserve raw
  `git` for authorized mutations.
- Do not hide gated actions in chains, pipes, command substitutions, wrappers,
  or scripts with unrelated lower-authority checks.
- The Pi MCP permission extension is the interactive approval gate for native
  MCP calls, including those made through `codemode`. Before a state-changing or
  ambiguous call, explain its server, tool, targets, expected effects, and
  rollback path when applicable; let the gate request confirmation rather than
  asking twice. Its approval covers only that call. Never treat a tool's own
  `confirm` flag or token, or an earlier broad request, as approval. If the
  gate is unavailable or the call bypasses it, ask with `ask_user_question`
  (or in chat if unavailable) and wait before proceeding.
- Remote repository operations require an explicit repository, remote, exact
  non-delete ref, action, and allowed state changes. Never force-push or delete
  a remote ref.
- Delegate only when explicitly authorized and the work is bounded and disjoint.
  Keep one writer per checkout; the parent retains decisions, integration, and
  final-verification ownership.

## Verification and Runtime Changes

- Verify the requested observable outcome, not only edits or exit codes. For UI
  and interactive behavior, exercise the real entry point when feasible and
  material to the outcome. Otherwise report static, mocked, or headless checks
  as source verification, not runtime confirmation.
- Report skipped, failed, timed-out, or state-changing checks as partial and name
  the smallest useful next check. Delegated success is evidence, not completion.
- Do not run `rebuild`, `darwin-rebuild`, `home-manager switch`, or equivalent
  activation unless the current request explicitly asks the LLM to run that
  class of operation. Editing, committing, or merging configuration does not
  authorize activation.
- Give network-backed work a finite deadline. Retry transient failed reads
  only when useful within that deadline; do not retry indefinitely. A timed-out
  mutation has unknown outcome. Read back its exact target before considering
  another mutation, and never retry it automatically.
