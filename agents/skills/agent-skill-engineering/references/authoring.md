# Authoring High-Quality Skills

Use this reference for Create and Improve work.

## Contents

- Artifact choice
- Evidence and acceptance
- Metadata and routing
- Progressive disclosure
- Workflows and scripts
- Portability
- Authoring checklist

## Artifact choice

Use a skill when a recurring task needs specialized context or procedure only
when relevant. Use another mechanism when it fits better:

| Need | Prefer |
| --- | --- |
| Rule relevant to nearly every task | Global or repository instructions |
| Short user-triggered request | Prompt template or command |
| Deterministic parsing, mutation, or policy | Script, extension, hook, or CI |
| External data/service integration | Tool or MCP server |
| Human explanation only | Documentation |
| Distinct role, tools, or model | Dedicated agent |

Do not create a skill merely because a workflow is complicated. Create it when
representative tasks show reusable context or procedure that the base model
repeatedly lacks.

## Evidence and acceptance

Before extensive documentation:

1. Collect at least three representative tasks when practical.
2. Run or reconstruct a no-skill baseline.
3. Record concrete failures, missing domain context, or inconsistent outputs.
4. Define the minimum behavior the skill must improve.
5. Include near-miss cases where the skill should not activate or should decline.
6. Name safety invariants and required verification.

For a new domain without enough evidence, produce a small charter and evidence
gaps rather than inventing a comprehensive package.

## Metadata and routing

The portable core requires:

- `name`: lowercase letters, digits, and single hyphens; 1–64 characters;
  matching directory name.
- `description`: 1–1024 characters; specific about both capability and when it
  applies.

Write descriptions in third person. Include discriminating nouns and verbs, plus
a near-miss boundary when confusion is likely. Avoid vague wording such as
“helps with files” and aggressive wording that makes the skill match unrelated
tasks.

Optional fields need justification:

- `license`: when distribution terms matter.
- `compatibility`: only for real environment requirements.
- `metadata`: only for a known consumer.
- `allowed-tools`: experimental and never the sole security boundary.
- Harness extensions such as explicit-only invocation: document what happens
  when another client ignores them.

## Progressive disclosure

Use three layers:

1. **Metadata:** name and description used for discovery.
2. **`SKILL.md`:** the activated router, procedure, and invariants.
3. **Resources:** task-selected detail loaded only when needed.

Keep `SKILL.md` well below 500 lines and preferably below roughly 5,000 tokens.
Every paragraph must justify its activated-context cost.

Resource rules:

- Link resources directly from `SKILL.md`; avoid reference-to-reference chains.
- Give every link a clear condition for reading it.
- Keep each reference focused on one decision or domain.
- Add a table of contents to references longer than about 100 lines.
- Do not duplicate the same rule across the body and references.
- Remove resources the agent never reads in real usage.

## Workflows and scripts

Use a clear sequence when ordering matters. Include validation loops such as:

`inspect → plan → validate → execute → verify`

Match specificity to fragility:

- High freedom: heuristics for open-ended work.
- Medium freedom: preferred patterns or parameterized templates.
- Low freedom: deterministic scripts and exact checks for fragile operations.

Add a script only when repeatability, reliability, or token savings justify
maintaining code. Scripts must:

- be self-contained or declare dependencies;
- fail with actionable errors;
- validate inputs and outputs;
- avoid implicit installation or network access;
- use pinned inputs when remote resolution is approved;
- state whether the agent should run the script or read it as reference.

For batch or consequential work, prefer a machine-verifiable intermediate plan
before mutation.

## Portability

Use the current Agent Skills specification as the format authority and current
target-client documentation for discovery and invocation behavior. Do not copy a
dated harness matrix into the package.

For each claimed client:

1. Record the exact client and version.
2. Confirm discovery roots, project trust, duplicate-name behavior, and
   permissions.
3. Confirm explicit activation.
4. Test implicit routing only when enabled.
5. Confirm resource paths and any extension fields.
6. Label untested clients unsupported rather than “portable.”

Useful live sources:

- <https://agentskills.io/specification>
- <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>
- <https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/add-skills>
- Target harness documentation installed or published for the tested version

## Authoring checklist

- [ ] A skill is the right artifact.
- [ ] Requirements come from real tasks or authoritative domain sources.
- [ ] Name, directory, and description route precisely.
- [ ] Activated instructions contain only necessary procedure and invariants.
- [ ] Conditional detail is in focused, directly linked resources.
- [ ] Degrees of freedom match task risk.
- [ ] Scripts are justified, bounded, and verifiable.
- [ ] Dependencies, network, permissions, and side effects are explicit.
- [ ] Positive, near-miss, failure, and safety cases exist.
- [ ] Behavior is compared with a baseline before claiming improvement.
- [ ] Current target-client behavior is tested rather than assumed.
