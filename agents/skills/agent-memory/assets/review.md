---
am_schema: agent-memory/v1
am_id: "review-<project>-<topic>"
am_project: "<project>"
am_type: review
am_status: draft
am_created: "YYYY-MM-DDTHH:MM:SS±HH:MM"
am_updated: "YYYY-MM-DDTHH:MM:SS±HH:MM"
am_source: "<review source>"
am_owner: "<reviewer>"
am_links: []
am_checks: ["not-run: <reason>"]
am_next: "<exact next action>"
---

# Review: <topic>

## Disposition

`<ready|ready with fixes|blocked|needs redesign|unsafe to exercise>`

## Scope reviewed

- `<paths, diffs, artifacts, or evidence>`

## Findings

### Blockers

- `<finding, evidence, impact, smallest fix>`

### Non-blocking

- `<finding, evidence, impact, smallest fix>`

## Validation

- Run: `<checks>`
- Not run: `<checks and reason>`

## Residual risks

- `<risk or none>`

## Next action

`<exact next action>`
