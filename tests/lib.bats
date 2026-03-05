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
