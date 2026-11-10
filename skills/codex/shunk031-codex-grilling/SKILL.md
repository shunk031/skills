---
name: shunk031-codex-grilling
description: Use whenever the grilling skill is invoked in Codex, including requests to grill or stress-test a plan, decision, or idea. Present its interview rounds through the native question UI.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `❓ I read shunk031-codex-grilling.`

# Grilling with the question UI

Read the installed `grilling` skill and follow it. This wrapper changes question presentation only; `grilling` owns the design tree, frontier rounds, investigation, and shared-understanding confirmation. If the dependency is unavailable, report that instead of reconstructing its instructions.

## Present each round

Use the available native question tool when its current rules permit the question. Prefer `request_user_input_async` when available; otherwise use `request_user_input`. Read the exposed tool schema rather than assuming a tool name, mode, or capacity is supported.

- Put each numbered question and its decision context in the question field, with concise choices and their consequences.
- Put the recommended answer first and label it as recommended. Preserve grilling's convention that “yes” accepts the recommendation.
- Keep free-form answers possible through the tool's supported mechanism; do not force an open question into misleading choices.
- When a frontier exceeds the tool's capacity, send it in batches within the same round. Keep the remaining frontier questions, and do not advance to dependent questions before their prerequisites are answered.
- Wait for answers as grilling requires. With an asynchronous tool, continue only independent fact-finding while the answers are pending.

Do not also repeat the UI questions as a prose questionnaire. Use grilling's prose format only when no native question UI is available or the tool's rules prevent its use for that question. Respect host restrictions, including restrictions on permission requests; do not reframe permission as a preference to bypass them.

## Handle interrupted questions

Cancellation or an empty response is not agreement. Keep the decision unresolved, incorporate any new user message, and do not immediately resend the same question. Follow host rules for proceeding with best judgment, but do not treat an assumption as the user's confirmation or as authorization to implement the design.
