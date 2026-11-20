# AGENTS

## Environment

- Git layouts vary. Resolve the real top-level, Git directory, branch, and
  registered worktrees instead of inferring them from the current path. Treat
  bare Git directories as infrastructure, not workspaces.

## Reporting

- Lead with the answer or the changes the user asked for. Leave out minor
  items, background, and routine steps unless the user asks for them.
- Give numbered options or next steps one plain sentence each: what it does
  and why. Name the ticket, PR, or file it concerns and mark the recommended one.
- When reporting that checks or tests ran, include the command and the decisive
  output line, or the log path.
- Cite the source (link, comment, or file:line) for facts taken from tickets,
  PRs, docs, or code.
- In multi-ticket or multi-session work, start each update by naming the
  current target.

## Writing as the User

- Before drafting text that will be posted under the user's name (Jira, PR
  descriptions and replies, chat, email), load `human-writing`.

## Credentials and External Systems

- Inspect non-secret metadata and effective configuration before credential use.
  Prefer configured host aliases, on-disk identity files, and existing local
  credential mechanisms.
- Before long or unattended work that needs cloud or GitHub access, run `creds`
  if it is installed, and ask the user to fix everything it reports in one
  message.
- Where `pass` is installed, use existing `pass` entries before `op`. Do not
  infer local lookup order from a repository's runtime secret source. Use
  1Password only when the local entry is absent, unusable, stale, or the task
  explicitly manages 1Password; network or route failures do not justify that
  fallback.
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
  A repository's `AGENTS.md` may pre-approve local integration and cleanup, but
  never push or activation.

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
- Create scratch directories with `mktemp -d /tmp/<task>.XXXXXX` instead of
  removing and recreating a fixed path. Remove them with `rm -r` (never
  `-f`), which does not prompt even in a chain or with a variable. Any
  `rm -rf` other than a standalone `rm -rf /tmp/<dir>` prompts for approval
  and stalls unattended workers.
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
- The primary interactive session is the coordinator. It owns reasoning,
  synthesis, small tasks, supervision, decisions, recovery, and final acceptance.
  This is standing authorization for that root session to delegate bounded,
  disjoint work when parallelism or context isolation materially helps; it is
  not authorization for new side effects or broader task scope. Explicit
  task-specific limits still win. Managed children must not delegate further.
- Before delegating or supervising multiple workstreams, load
  `coordinator-workflow` and the relevant orchestration skill. Keep one writer
  per checkout and at most three active managed workers across runs by policy;
  the coordinator retains integration and final-verification ownership. All
  credential, MCP approval, remote, activation, and cleanup gates still apply.

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
- When the user does ask for a rebuild, run `rebuild` in a visible Rex split so
  they can authenticate, for example `rex split -s "$REX_SESSION" -b "$REX_BLOCK"
  --split=below --label rebuild --keep-open --wait -c <repo> --shell=none --
  rebuild ...`. Always pass `--repo` and `--commit-message` with a Conventional
  Commit subject (remote mode cannot commit). Never use `sudo -n` or call
  `darwin-rebuild` directly. Report the `Result:` line. When the repository's
  `AGENTS.md` gives a rebuild command, use that exact command.
- Give network-backed work a finite deadline. Retry transient failed reads
  only when useful within that deadline; do not retry indefinitely. A timed-out
  mutation has unknown outcome. Read back its exact target before considering
  another mutation, and never retry it automatically.
