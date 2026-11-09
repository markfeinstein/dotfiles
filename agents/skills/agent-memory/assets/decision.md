---
am_schema: agent-memory/v1
am_id: "decision-<project>-<topic>"
am_project: "<project>"
am_type: decision
am_status: proposed
am_created: "YYYY-MM-DDTHH:MM:SS±HH:MM"
am_updated: "YYYY-MM-DDTHH:MM:SS±HH:MM"
am_source: "<source evidence>"
am_owner: "<decision owner>"
am_supersedes: []
am_links: []
am_next: "<exact next action>"
---

# Decision: <topic>

## Status

`proposed` or `accepted`. Proposed decisions are not authority to act.

## Decision

`<choice>`

## Context

- `<problem and constraints>`

## Options considered

- `<option>: <evidence, tradeoff, reason accepted/rejected>`

## Evidence

- `<source evidence and dates>`

## Consequences

- `<expected effects and follow-up checks>`

## Supersession

- Supersedes: `<full vault-relative links or none>`
- Superseded by: `<full vault-relative links or none>`

## Next action

`<exact next action>`
