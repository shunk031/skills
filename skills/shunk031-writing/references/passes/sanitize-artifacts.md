# Sanitize artifacts

Remove prompt echoes, conversation history, intermediate reasoning, tool choices, avoided approaches, production constraints, copied prompt examples, and explanations of why the artifact was written a certain way. Keep a constraint visible only when the intended reader needs it. Rewrite production guidance as audience-facing content instead of reporting the production process.

Remove bookkeeping labels and research-session narration such as `VERIFIED`, `HYPOTHESIS`, and `Unverified:`. Express uncertainty with a plain-language hedge, and keep a caveat only when the intended reader needs it, stating its scope or condition instead of describing the research process.

Specimen: "Treat the conversation as production context, not automatically as artifact content."

Source: https://github.com/kotek-7/dotfiles/blob/d80c707025bc138ce826917651c046fed232ee18/dot_agents/skills/sanitize-artifacts/SKILL.md
