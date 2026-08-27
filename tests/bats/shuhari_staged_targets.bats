#!/usr/bin/env bats

readonly WRAPPER="./scripts/shuhari_staged_targets.sh"
readonly TARGET_RELATIVE="skills/shunk031-cgd-dev-identity/SKILL.md"

setup() {
    local stub_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${stub_bin}"

    SHUHARI_ARGV_LOG="${BATS_TEST_TMPDIR}/shuhari-argv"
    SHUHARI_STUB_PATH="${stub_bin}/shuhari"
    export SHUHARI_ARGV_LOG SHUHARI_STUB_PATH

    cat > "${stub_bin}/mise" << 'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "which" ] && [ "${2:-}" = "shuhari" ]; then
    printf '%s\n' "${SHUHARI_STUB_PATH}"
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
exit 0
EOF
    chmod +x "${stub_bin}/mise" "${stub_bin}/shuhari" "${stub_bin}/uv"
    PATH="${stub_bin}:${PATH}"
    export PATH
}

function target_path() {
    local repo_root
    repo_root="$(cd -- "${BATS_TEST_DIRNAME}/../.." && pwd)"
    printf '%s/%s\n' "${repo_root}" "${TARGET_RELATIVE}"
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
