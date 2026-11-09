---
am_schema: agent-memory/v1
am_id: "plan-<project>-<objective>"
am_project: "<project>"
am_type: plan
am_status: draft
am_created: "YYYY-MM-DDTHH:MM:SS±HH:MM"
am_updated: "YYYY-MM-DDTHH:MM:SS±HH:MM"
am_source: "<source evidence>"
am_owner: "<owner>"
am_supersedes: []
am_links: []
am_reached_state: "source-only"
am_checks: ["not-run: <reason>"]
am_next: "<exact next action>"
---

# Plan: <objective>

## Outcome

`<desired terminal state>`

## Scope

- In scope: `<paths, behaviors, artifacts>`
- Out of scope: `<excluded work>`

## Steps

1. `<step>`
2. `<step>`

## Evidence and decisions

- `<source evidence>`
- Decisions needed: `<none or exact decision>`

## Checks

- Run: `<checks>`
- Not run: `<checks and reason>`

## Reached state

`<source-only|committed|merged|activated|runtime-observed|blocked|superseded|...>`

## Risks

- `<risk or none>`

## Next action

`<exact next action>`
