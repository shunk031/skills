# Independent review checklist

Use this checklist for every fresh independent review, including a Codex review while meta is usage-limited.

1. Confirm the repository and exact committed HEAD under review. Review only the change at that HEAD; report if the checked-out revision differs.
2. Read the task's acceptance criteria and design record. Inspect the complete diff and each changed file with enough surrounding source to understand its callers and contracts.
3. Reconstruct affected behavior from its authoritative source. Check correctness, regressions, error and edge handling, security and privacy, interfaces, and documentation consistency.
4. Inspect tests and gate evidence. Verify tests exercise the production path rather than a test-only reconstruction. In a read-only review, run only checks that cannot modify the checkout; otherwise assess the recorded results and test code.
5. Check citations, source attribution, numeric claims, and required design-record elements when the change includes them.
6. Return `ACCEPT` only when no actionable finding remains. For `REJECT`, list each finding with severity, exact path and line, and the evidence or scenario that demonstrates it. Keep advisory notes separate from blocking findings.
7. Keep the review read-only. Do not edit files, commit, push, or delegate the review.
