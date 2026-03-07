#!/usr/bin/env bats

# Unit tests for scripts/lib.sh (retry function).

setup() {
  export MOCK_DIR="$(mktemp -d)"

  # No-op sleep mock to avoid real delays.
  cat > "${MOCK_DIR}/sleep" <<'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "${MOCK_DIR}/sleep"
  export PATH="${MOCK_DIR}:${PATH}"

  export SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../scripts" && pwd)"
  source "${SCRIPT_DIR}/lib.sh"
}

teardown() {
  rm -rf "${MOCK_DIR}"
}

@test "retry: succeeds on first attempt" {
  run retry 3 2 true
  [ "${status}" -eq 0 ]
}

@test "retry: succeeds after transient failure" {
  # Counter file tracks attempts.
  local counter_file="${MOCK_DIR}/counter"
  echo "0" > "${counter_file}"

  cat > "${MOCK_DIR}/flaky.sh" <<MOCK
#!/bin/bash
count=\$(cat "${counter_file}")
count=\$((count + 1))
echo "\${count}" > "${counter_file}"
if [ "\${count}" -lt 2 ]; then
  exit 1
fi
exit 0
MOCK
  chmod +x "${MOCK_DIR}/flaky.sh"

  run retry 3 1 "${MOCK_DIR}/flaky.sh"
  [ "${status}" -eq 0 ]
}

@test "retry: fails after max retries exhausted" {
  run retry 3 1 false
  [ "${status}" -ne 0 ]
}

@test "retry: preserves stdout from successful attempt" {
  result="$(retry 3 1 echo "hello world")"
  [ "${result}" = "hello world" ]
}

@test "random_delim: produces prefix followed by 32 hex chars" {
  result="$(random_delim MY_PREFIX)"
  # Should start with the prefix.
  [[ "${result}" == MY_PREFIX_* ]]
  # Extract the random suffix (everything after "MY_PREFIX_").
  suffix="${result#MY_PREFIX_}"
  # Suffix should be 32 hex characters.
  [ "${#suffix}" -eq 32 ]
  [[ "${suffix}" =~ ^[0-9a-f]{32}$ ]]
}

@test "random_delim: produces unique values" {
  result1="$(random_delim TEST)"
  result2="$(random_delim TEST)"
  [ "${result1}" != "${result2}" ]
}

@test "build_flags: populates array from space-separated values" {
  build_flags my_arr "--zone" "a.com b.com"
  [ "${#my_arr[@]}" -eq 4 ]
  [ "${my_arr[0]}" = "--zone" ]
  [ "${my_arr[1]}" = "a.com" ]
  [ "${my_arr[2]}" = "--zone" ]
  [ "${my_arr[3]}" = "b.com" ]
}

@test "build_flags: empty string produces empty array" {
  build_flags my_arr "--zone" ""
  [ "${#my_arr[@]}" -eq 0 ]
}

@test "build_flags: single value produces two-element array" {
  build_flags my_arr "--phase" "cache_rules"
  [ "${#my_arr[@]}" -eq 2 ]
  [ "${my_arr[0]}" = "--phase" ]
  [ "${my_arr[1]}" = "cache_rules" ]
}

@test "require_octorules: succeeds when octorules is on PATH" {
  cat > "${MOCK_DIR}/octorules" <<'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "${MOCK_DIR}/octorules"
  run require_octorules
  [ "${status}" -eq 0 ]
}

@test "require_octorules: fails with message when octorules is missing" {
  # Remove any mock octorules so command -v fails.
  rm -f "${MOCK_DIR}/octorules"
  # Write a helper script that sources lib.sh and calls require_octorules
  # with a PATH that has no octorules binary.
  cat > "${MOCK_DIR}/test_require.sh" <<SCRIPT
#!/bin/bash
export PATH="${MOCK_DIR}"
source "${SCRIPT_DIR}/lib.sh"
require_octorules
SCRIPT
  chmod +x "${MOCK_DIR}/test_require.sh"
  run bash "${MOCK_DIR}/test_require.sh"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"octorules not found on PATH"* ]]
}

@test "run_capturing: captures stdout to file" {
  local out_file="${MOCK_DIR}/out.log"
  local err_file="${MOCK_DIR}/err.log"
  run_capturing "${out_file}" "${err_file}" echo "hello stdout"
  [ "${_exit_code}" -eq 0 ]
  [[ "$(cat "${out_file}")" == *"hello stdout"* ]]
}

@test "run_capturing: captures stderr to file" {
  local out_file="${MOCK_DIR}/out.log"
  local err_file="${MOCK_DIR}/err.log"
  run_capturing "${out_file}" "${err_file}" bash -c 'echo "hello stderr" >&2'
  [ "${_exit_code}" -eq 0 ]
  [[ "$(cat "${err_file}")" == *"hello stderr"* ]]
}

@test "run_capturing: sets _exit_code on failure" {
  local out_file="${MOCK_DIR}/out.log"
  local err_file="${MOCK_DIR}/err.log"
  run_capturing "${out_file}" "${err_file}" false
  [ "${_exit_code}" -ne 0 ]
}

@test "warn_unexpected: no warning for allowed value" {
  run warn_unexpected "FORCE" "Yes" "Yes No"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "warn_unexpected: warns for unexpected value" {
  run warn_unexpected "FORCE" "maybe" "Yes No"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARN: Unexpected value for FORCE"* ]]
  [[ "${output}" == *"'maybe'"* ]]
}

@test "warn_unexpected: no warning for empty value" {
  run warn_unexpected "DOIT" "" "--doit"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "retry: warns on stderr between retries" {
  # Capture stderr from a command that fails once then succeeds.
  local counter_file="${MOCK_DIR}/counter"
  echo "0" > "${counter_file}"

  cat > "${MOCK_DIR}/flaky.sh" <<MOCK
#!/bin/bash
count=\$(cat "${counter_file}")
count=\$((count + 1))
echo "\${count}" > "${counter_file}"
if [ "\${count}" -lt 2 ]; then
  exit 1
fi
exit 0
MOCK
  chmod +x "${MOCK_DIR}/flaky.sh"

  run retry 3 1 "${MOCK_DIR}/flaky.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARN: Attempt 1/3 failed"* ]]
}
