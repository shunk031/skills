#!/usr/bin/env bats

# The wrapper resolves every target against the repository root derived from
# its own location, so setup copies it into a disposable repository populated
# with a synthetic skill. That keeps these tests valid no matter which real
# skills currently carry evals/evals.json or evals/triggers.json.
#
# Most tests inspect the argv the wrapper builds and answer `mise which` with a
# stub that records it. The validate-mode test instead answers with the pinned
# Shuhari, because the behavior it covers lives in that binary: Shuhari reads
# SHUHARI_SANDBOX from the environment itself, so no stub can reproduce it. The
# fixture's eval files are therefore schema-valid rather than minimal.

setup() {
    local stub_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${stub_bin}"

    # Resolved before the stub `mise` joins PATH, so this finds the real one.
    PINNED_SHUHARI="$(cd "${BATS_TEST_DIRNAME}/../.." && \
        MISE_ENABLE_TOOLS='go:github.com/shunk031/shuhari/cmd/shuhari' \
            mise which shuhari 2> /dev/null || true)"
    export PINNED_SHUHARI

    local fixture_root="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${fixture_root}/scripts"
    cp "${BATS_TEST_DIRNAME}/../../scripts/shuhari_staged_targets.sh" \
        "${fixture_root}/scripts/shuhari_staged_targets.sh"
    WRAPPER="${fixture_root}/scripts/shuhari_staged_targets.sh"

    local skill_dir="${fixture_root}/skills/override-fixture"
    mkdir -p "${skill_dir}/evals"
    cat > "${skill_dir}/SKILL.md" << 'EOF'
---
name: override-fixture
description: Synthetic fixture skill for the wrapper unit tests. Never installed.
---

# Override Fixture

Fixture body.
EOF
    cat > "${skill_dir}/evals/evals.json" << 'EOF'
{
  "skill_name": "override-fixture",
  "evals": [
    {
      "id": "fixture-case",
      "prompt": "Fixture prompt.",
      "expected_output": "Fixture output.",
      "assertions": ["The response mentions the fixture."]
    }
  ]
}
EOF
    cat > "${skill_dir}/evals/triggers.json" << 'EOF'
{
  "skill_name": "override-fixture",
  "cases": [
    {"id": "positive", "prompt": "Fixture positive prompt.", "should_trigger": true},
    {"id": "negative", "prompt": "Fixture negative prompt.", "should_trigger": false}
  ]
}
EOF
    TARGET="${skill_dir}/SKILL.md"

    SHUHARI_ARGV_LOG="${BATS_TEST_TMPDIR}/shuhari-argv"
    UV_ARGV_LOG="${BATS_TEST_TMPDIR}/uv-argv"
    # What the stub `mise which shuhari` answers. Tests that need the real
    # binary point it there instead.
    SHUHARI_RESOLVED_PATH="${stub_bin}/shuhari"
    export SHUHARI_ARGV_LOG SHUHARI_RESOLVED_PATH UV_ARGV_LOG

    cat > "${stub_bin}/mise" << 'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "which" ] && [ "${2:-}" = "shuhari" ]; then
    printf '%s\n' "${SHUHARI_RESOLVED_PATH}"
    exit 0
fi
exit 1
EOF
    cat > "${stub_bin}/shuhari" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${SHUHARI_ARGV_LOG}"
EOF
    cat > "${stub_bin}/uv" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${UV_ARGV_LOG}"
exit 0
EOF
    chmod +x "${stub_bin}/mise" "${stub_bin}/shuhari" "${stub_bin}/uv"
    PATH="${stub_bin}:${PATH}"
    export PATH
}

function target_path() {
    printf '%s\n' "${TARGET}"
}

@test "SHUHARI_RECORD_RESULTS false keeps pre-commit evaluation read-only" {
    local target
    target="$(target_path)"

    run env SHUHARI_RECORD_RESULTS=false "${WRAPPER}" eval "${target}"
    [ "${status}" -eq 0 ]
    [ ! -e "${UV_ARGV_LOG}" ]
}

@test "validation ignores an exported SHUHARI_SANDBOX" {
    if [ -z "${PINNED_SHUHARI}" ] || [ ! -x "${PINNED_SHUHARI}" ]; then
        echo "pinned shuhari not installed; run 'make setup'" >&2
        return 1
    fi

    local target
    target="$(target_path)"

    # Schema validation starts no agent, so the sandbox the wrapper is told to
    # use elsewhere must not reach it. Shuhari rejects an unsandboxed level
    # without --network, which turned an offline parse into a failing gate.
    run env SHUHARI_SANDBOX=unsandboxed \
        SHUHARI_RESOLVED_PATH="${PINNED_SHUHARI}" \
        "${WRAPPER}" validate "${target}"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"cannot honor sandbox level"* ]]
}

@test "unset overrides preserve the trigger argv" {
    local target expected
    target="$(target_path)"
    expected="${BATS_TEST_TMPDIR}/expected"
    printf '%s\n' \
        check \
        trigger \
        "${target%/SKILL.md}" \
        --progress \
        --model gpt-5.6-luna \
        --reasoning-effort high \
        --trials 3 \
        --jobs 8 \
        --timeout 600 > "${expected}"

    run env -u SHUHARI_SANDBOX -u SHUHARI_AGENT_EXECUTABLE -u SHUHARI_JOBS \
        -u SHUHARI_ALLOW_TOOLS -u SHUHARI_MODE \
        -u SHUHARI_TIMEOUT "${WRAPPER}" trigger "${target}"
    [ "${status}" -eq 0 ]

    run diff -u "${expected}" "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]

    ! grep -Fx -- '--mode' "${SHUHARI_ARGV_LOG}" > /dev/null
}

@test "SHUHARI_MODE completion reaches both gates" {
    local target
    target="$(target_path)"

    run env SHUHARI_MODE=completion "${WRAPPER}" trigger "${target}"
    [ "${status}" -eq 0 ]
    run grep -cFx -- '--mode' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    [ "${output}" -eq 1 ]
    run grep -cFx -- 'completion' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    [ "${output}" -eq 1 ]

    run env SHUHARI_MODE=completion "${WRAPPER}" eval "${target}"
    [ "${status}" -eq 0 ]
    run grep -cFx -- '--mode' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    [ "${output}" -eq 1 ]
    run grep -cFx -- 'completion' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    [ "${output}" -eq 1 ]
}

@test "invalid SHUHARI_MODE fails clearly" {
    local target
    target="$(target_path)"

    run env SHUHARI_MODE=invalid "${WRAPPER}" trigger "${target}"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"Invalid SHUHARI_MODE 'invalid'; expected agentic or completion."* ]]
}

@test "environment overrides add trigger flags and network for unsandboxed runs" {
    local target expected
    target="$(target_path)"
    expected="${BATS_TEST_TMPDIR}/expected"
    printf '%s\n' \
        check \
        trigger \
        "${target%/SKILL.md}" \
        --allow-tool \
        codex-genai-token \
        --allow-tool \
        fnox \
        --sandbox \
        unsandboxed \
        --network \
        --agent-executable \
        /usr/local/bin/codex-wrapper \
        --progress \
        --model gpt-5.6-luna \
        --reasoning-effort high \
        --trials 3 \
        --jobs 4 \
        --timeout 42 > "${expected}"

    run env SHUHARI_SANDBOX=unsandboxed \
        SHUHARI_AGENT_EXECUTABLE=/usr/local/bin/codex-wrapper \
        SHUHARI_JOBS=4 SHUHARI_TIMEOUT=42 \
        SHUHARI_ALLOW_TOOLS='codex-genai-token fnox' \
        "${WRAPPER}" trigger "${target}"
    [ "${status}" -eq 0 ]

    run diff -u "${expected}" "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
}

@test "environment overrides reach eval without changing pinned measurements" {
    local target
    target="$(target_path)"

    run env SHUHARI_SANDBOX=read-only SHUHARI_AGENT_EXECUTABLE=/tmp/agent \
        SHUHARI_ALLOW_TOOLS='codex-genai-token fnox' \
        SHUHARI_JOBS=1 SHUHARI_TIMEOUT=9 \
        "${WRAPPER}" eval "${target}"
    [ "${status}" -eq 0 ]

    run grep -F -- '--sandbox' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- 'read-only' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- '--agent-executable' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- '/tmp/agent' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -cFx -- '--allow-tool' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    [ "${output}" -eq 2 ]
    run grep -Fx -- 'codex-genai-token' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- 'fnox' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- '--jobs' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- '1' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- '--timeout' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- '9' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- '--trials' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- '3' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- '--model' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- 'gpt-5.6-luna' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- '--judge-model' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- 'gpt-5.6-sol' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- '--reasoning-effort' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- 'high' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- '--judge-reasoning-effort' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
    run grep -Fx -- 'medium' "${SHUHARI_ARGV_LOG}"
    [ "${status}" -eq 0 ]
}
