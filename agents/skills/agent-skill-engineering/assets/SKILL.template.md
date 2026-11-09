---
name: skill-name
description: Describes what the skill does and when it should be used.
---

# Skill title

State the outcome this skill helps produce. Assume the model already knows
general concepts.

## Scope

Use this skill for:

- <specific recurring task>
- <another positive trigger>

Do not use it for:

- <near miss or adjacent task>
- <operation requiring a different artifact or permission>

## Procedure

1. Resolve the exact target, inputs, authority, and acceptance criteria.
2. Read only the task-selected references.
3. Perform the smallest coherent workflow.
4. Validate the observable result.
5. Report results, skipped checks, risks, and the next action.

## Invariants

- <must always remain true>
- <safety or privacy boundary>
- <condition that requires stopping>

## Resources

- `references/reference.md` — read only when <condition>.
- `scripts/validator.py` — run when <condition>; document dependencies and
  expected output.

Remove unused sections and resources. Add examples only when they materially
improve output quality or disambiguate a contract.
