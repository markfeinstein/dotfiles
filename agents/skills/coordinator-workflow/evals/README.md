# Coordinator workflow evaluation plan

These are unexecuted behavioral cases, not passing evaluations. The structural
validator checks package shape and fixture completeness only.

Baseline: shared dotfiles commit `e9222cd`, without this skill or standing
coordinator delegation policy. Candidate: the delivered commit containing this
skill and its paired global instructions. Keep tools, model, task environment,
and authorization identical between runs; record candidate skill/global-policy
digests so the combined change is not attributed to the skill alone.

For a future authorized evaluation:

1. Use fresh isolated Pi sessions with mocked consequential actions. Record exact
   Pi/model/package versions, discovered skills, tool inventory, and trust state.
2. Check discovery and explicit `/skill:coordinator-workflow` activation before
   implicit routing. No live worker or external mutation is needed for these
   policy scenarios.
3. Run both baseline and candidate on each case. Grade observable actions against
   `expected`; don't require matching prose. Record routing, instruction use,
   outcome, safety violations, and tool/token cost separately.
4. Repeat stochastic cases; have an independent reviewer grade blinded outputs
   if an improvement claim is intended. Keep raw outputs or durable summaries.
5. Stop on an unauthorized action. Never turn a mock result into runtime proof.

Target documentation reviewed: installed Pi 1.5.2 `docs/skills.md` and the Agent
Skills specification on 2026-11-17. Real automatic routing, skill efficacy,
worker-side guardrails, other harnesses, and aggregate policy compliance are
**not yet evaluated**. A local real-Pi/Rex restoration smoke test in the separate
pi-subagents source repository verifies transport/session behavior, not this
skill's decisions.
