# Eval authoring

Use [Anthropic skill-creator's `evals.json` schema](https://github.com/anthropics/claude-plugins-official/blob/main/plugins/skill-creator/skills/skill-creator/references/schemas.md#evalsjson): the top-level `skill_name` must match the skill frontmatter, and each case has an integer `id`, `prompt`, and `expected_output`. Optional `files` and `expectations` provide input files and verifiable success criteria.

Write `expected_output` in one to three sentences describing the behavior that should result, not the wording of a good reply. Keep each case focused and make every expectation check only what its prompt asks for. Split a case that asks several independent questions.

Judge substance rather than exact wording. If a case checks behavior already common without the skill, keep the instruction in `SKILL.md` and remove the case instead of sharpening it until a difference appears.

This repository stores these cases but does not run or grade them. Do not describe them as a local gate or claim that a change passed them.
