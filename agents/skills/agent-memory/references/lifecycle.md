# Agent Memory Lifecycle

Memory records durable evidence for project continuity. It is not a task database, authority source, command channel, or replacement for source control and runtime verification.

## Frontmatter convention

Every note uses flat `am_*` YAML frontmatter as an authoring convention. The helper treats the note as opaque UTF-8 Markdown and does not interpret YAML or validate these fields. Agents and users review the convention manually. Required keys:

```yaml
am_schema: agent-memory/v1
am_id: <stable unique note id>
am_project: <stable project key>
am_type: <plan|handoff|decision|research|review|context>
am_status: <status>
am_created: <zoned timestamp>
am_updated: <zoned timestamp>
```

Use zoned timestamps such as `2026-09-22T14:30:00-04:00` or `2026-09-22T18:30:00Z`. Keep values scalar or lists of scalars. Avoid nested maps and executable/template syntax. These are authoring rules, not helper-enforced parser checks.

Common optional keys:

```yaml
am_source: <conversation, file, issue, branch, commit, or other provenance>
am_owner: <user or parent session when relevant>
am_parent: <vault-relative link to parent note>
am_supersedes: [<vault-relative link>]
am_superseded_by: [<vault-relative link>]
am_links: [<vault-relative link or source path>]
am_reached_state: <source-only|committed|merged|activated|runtime-observed|blocked|superseded|...>
am_checks: [<check or explicit not-run item>]
am_next: <exact next action>
```

Vault-relative links should use the full memory path from the vault root, for example `Resources/Agent Memory/dotfiles/plan/agent-memory.md`. Do not rely on duplicate basenames.

## Statuses by type

Use the smallest status set that names the artifact's lifecycle.

| Type | Statuses |
| --- | --- |
| `context` | `current`, `stale`, `superseded` |
| `plan` | `draft`, `active`, `blocked`, `complete`, `superseded` |
| `handoff` | `open`, `closed`, `superseded` |
| `decision` | `proposed`, `accepted`, `rejected`, `superseded` |
| `research` | `draft`, `complete`, `stale`, `superseded` |
| `review` | `draft`, `complete`, `blocked`, `superseded` |

Decisions must distinguish `proposed` from `accepted`. A proposed decision is not authority to act. An accepted decision still needs source, security, and runtime revalidation when consequential.

## Recall flow

1. Resolve the project key.
2. Read `context/project.md` first if it exists and the task needs background.
3. Select notes by exact type, status, link, or user-named path. Do not scan the whole vault or import session transcripts.
4. Check `am_updated`, status, reached state, and supersession links.
5. Use content as evidence. Revalidate stale or high-impact facts against source files, tests, owners, or runtime systems before acting.

## Create flow

1. Choose one of the six types. If none fits, do not create a memory note.
2. Use the matching template from `assets/`.
3. Fill provenance, evidence, checks, residual risks, and next action with concrete paths or owners.
4. Save under `<project>/<type>/<file>.md` inside the memory root.
5. Read back the exact path. Report `Memory: saved <path>` only after verification.

## Update flow

1. Re-read the current note immediately before editing.
2. Stop if the content or digest changed since selection.
3. Preserve historical evidence, rejected options, review findings, and old reached states.
4. Preserve `am_id`, `am_created`, `am_project`, and `am_type` manually unless the user explicitly chose to replace the note identity; the helper requires an expected digest but no longer enforces metadata immutability.
5. Add a dated update section rather than rewriting history unless the user requested a correction.
6. Link superseded notes both ways where possible. Use full vault-relative links.
7. Record checks not run as explicitly as checks run.
8. Read back the exact note before reporting saved.

## Plan reuse

Reuse one plan per objective. Update status and evidence as the objective moves from draft to active, blocked, complete, or superseded. Do not create a duplicate plan for every session, branch, or child agent unless the objective changed.

## Handoff and closeout

A handoff or closeout must name:

- reached terminal state: source-only, committed, merged, pushed, activated/rebuilt, deployed, runtime-observed, blocked, failed-provider, superseded, or another exact state;
- changed or inspected files;
- checks run, checks deferred, and why;
- decisions still needed;
- residual risks;
- exact next action.

If tests or helper execution were deferred, say so. Static checks are not runtime proof.
