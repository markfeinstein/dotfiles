# Evaluating Skills

Use this reference before claiming that a skill works, adds value, or improves
over another version.

## Contents

- Define the claim
- Build cases
- Separate evaluation layers
- Run matched comparisons
- Interpret results
- Iterate and stop

## Define the claim

State exactly what should improve:

- discovery or explicit activation;
- compliance with a domain rule;
- output correctness or completeness;
- safe refusal or permission behavior;
- task success;
- efficiency, latency, or context use.

Do not use one score to stand in for all of these. Name the harness, model,
skill digest, available tools, and environment.

## Build cases

Use real or realistic tasks that represent the intended distribution. Include:

- positive cases that should use the skill;
- near misses that should not use it;
- ambiguous cases that should clarify;
- malformed and failure cases;
- adversarial or safety cases;
- representative long-context or multi-skill composition cases when relevant.

Keep development cases separate from final evaluation cases when practical.
Three strong cases are a useful minimum for a narrow skill, not proof of broad
coverage.

Each case should define observable expected behavior rather than requiring exact
wording unless wording is the product contract.

## Separate evaluation layers

### Routing

Did the correct skill become visible and load under the intended invocation
policy? Explicit-only skills should be tested for command visibility and direct
activation, not implicit selection.

### Instruction use

Did the model apply the relevant rule or resource? Distinguish loading the skill
from incorporating it correctly.

### Task outcome

Did the real task succeed according to domain acceptance criteria? Prefer
deterministic validators or source/runtime evidence over stylistic judgment.

### Safety

Did the skill avoid forbidden actions, protect sensitive information, preserve
scope, and stop at approval boundaries?

### Efficiency

Measure tokens, tool calls, latency, or repeated reads only when efficiency is a
claim. Fewer tokens are not automatically better if reliability falls.

## Run matched comparisons

For Create or Improve claims, compare:

1. no skill or the frozen prior version;
2. the candidate skill;
3. identical cases, tools, environment, and grading criteria.

Use fresh sessions so prior activation and conversation state do not contaminate
results. Test every model/harness cell you intend to support; otherwise label it
untested.

Use deterministic graders where possible. When model or human judgment is
needed:

- keep the rubric short and case-specific;
- hide candidate identity when practical;
- separate author and grader for consequential claims;
- retain raw outputs or durable summaries sufficient to reproduce the finding;
- report disagreements and uncertainty.

Repeat stochastic cases enough to detect instability, but do not manufacture
precision from a tiny sample.

## Interpret results

Report:

- case set and environment;
- baseline and candidate digests;
- passes, failures, and regressions by layer;
- safety violations separately from quality;
- cases solved by only one variant;
- tool/provider failures and excluded runs;
- unsupported cells and confidence.

A candidate can have the same aggregate success while solving different cases.
Inspect differences, not only totals.

## Iterate and stop

Change the smallest instruction or resource likely to address an observed
failure, then rerun affected cases and a regression subset. Remove content that
is ignored or causes collisions.

Stop when acceptance criteria are met and no material regression remains. Do
not keep adding guidance merely because another plausible rule can be written.
If there is no measurable improvement over the baseline, prefer no skill or a
smaller package.
