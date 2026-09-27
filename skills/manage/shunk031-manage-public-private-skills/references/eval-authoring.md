# Eval authoring

Behavior cases in `evals/evals.json` require `id`, `prompt`, and `expected_output`; `assertions` and `files` are optional. Trigger cases in `evals/triggers.json` need at least one positive case and one near-miss negative control.

Write `expected_output` in one to three sentences describing the behavior that should result, not the wording of a good reply. Do not restate the assertions. Shuhari compares with-skill and without-skill outputs as well as grading assertions, so repeated assertion text biases that comparison.

Make negative controls near misses. A control that shares the skill's vocabulary while not calling for it measures the boundary; an unrelated prompt measures nothing.

An assertion may test only what its own prompt asks for. If another behavior matters, write another case whose prompt asks for it. Do not require a warning, execution, or explanation that the prompt did not request.

Keep each case focused. A trial passes only when every assertion passes, and a case needs a majority of trials. Split a case that asks several independent questions. Re-measure a result that changes across three trials before treating it as a finding; use five trials when the decision matters.

Judge substance rather than exact wording. If both arms pass every trial, keep the rule in `SKILL.md` and delete the non-discriminating case instead of sharpening it until a difference appears.

Runs are offline by default. Mark a live-network behavior case with `evals/network-required`; the gate skips it and records why. Keep the case so it can be restored when network research becomes available.

Run the gates in this order: `--validate-only`, `shuhari check trigger`, then `shuhari eval skill`. The first is offline, the second checks invocation, and the third compares both arms.
