---
am_schema: agent-memory/v1
am_id: "handoff-<project>-<topic>-YYYYMMDD"
am_project: "<project>"
am_type: handoff
am_status: open
am_created: "YYYY-MM-DDTHH:MM:SS±HH:MM"
am_updated: "YYYY-MM-DDTHH:MM:SS±HH:MM"
am_source: "<source evidence>"
am_owner: "<owner>"
am_links: []
am_reached_state: "source-only"
am_checks: ["not-run: <reason>"]
am_next: "<exact next action>"
---

# Handoff: <topic>

## Reached state

`<source-only|committed|merged|pushed|activated/rebuilt|deployed|runtime-observed|blocked|failed-provider|superseded|...>`

## What changed or was inspected

- `<path or artifact>: <summary>`

## Evidence

- `<dated source, command result, review, or owner statement>`

## Checks

- Run: `<checks>`
- Deferred or not run: `<checks and reason>`

## Decisions needed

- `<decision or none>`

## Residual risks

- `<risk or none>`

## Exact next action

`<command, decision, review, or handoff step>`
