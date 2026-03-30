#!/usr/bin/env bats

# Unit tests for scripts/audit.sh
# Uses PATH-override mocking: a temp directory with a fake `octorules`
# script is prepended to $PATH.

setup() {
  export MOCK_DIR="$(mktemp -d)"
  export GITHUB_WORKSPACE="$(mktemp -d)"
  export GITHUB_OUTPUT="$(mktemp)"
  export CONFIG_PATH="config.yaml"
  export AUDIT="Yes"
  export AUDIT_CHECKS=""
  export PHASES=""
  export ZONES=""

  # Record file: the mock writes its arguments here.
  export MOCK_ARGS_FILE="${MOCK_DIR}/octorules.args"
  # Exit code file: controls the mock's exit code.
  export MOCK_EXIT_FILE="${MOCK_DIR}/octorules.exit"
  echo "0" > "${MOCK_EXIT_FILE}"

  # Create mock octorules that records args and exits with configured code.
  cat > "${MOCK_DIR}/octorules" <<'MOCK'
#!/bin/bash
echo "$@" > "${MOCK_ARGS_FILE}"
exit "$(cat "${MOCK_EXIT_FILE}")"
MOCK
  chmod +x "${MOCK_DIR}/octorules"

  # Prepend mock dir to PATH.
  export PATH="${MOCK_DIR}:${PATH}"

  # Resolve the script under test.
  export SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../scripts" && pwd)"
}

teardown() {
  rm -rf "${MOCK_DIR}" "${GITHUB_WORKSPACE}" "${GITHUB_OUTPUT}"
}

# ---------- Env var validation ----------

@test "fails when CONFIG_PATH unset" {
  unset CONFIG_PATH
  run bash "${SCRIPT_DIR}/audit.sh"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"CONFIG_PATH"* ]]
}

@test "fails when GITHUB_WORKSPACE unset" {
  unset GITHUB_WORKSPACE
  run bash "${SCRIPT_DIR}/audit.sh"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"GITHUB_WORKSPACE"* ]]
}

@test "fails when GITHUB_OUTPUT unset" {
  unset GITHUB_OUTPUT
  run bash "${SCRIPT_DIR}/audit.sh"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"GITHUB_OUTPUT"* ]]
}

# ---------- Skip conditions ----------

@test "skip when AUDIT != Yes" {
  AUDIT="No" run bash "${SCRIPT_DIR}/audit.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"SKIP"* ]]
}

@test "skip when AUDIT is empty" {
  AUDIT="" run bash "${SCRIPT_DIR}/audit.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"SKIP"* ]]
}

@test "skip: outputs empty audit_exit_code and audit_results" {
  AUDIT="No" run bash "${SCRIPT_DIR}/audit.sh"
  [ "${status}" -eq 0 ]
  grep -q "audit_exit_code=$" "${GITHUB_OUTPUT}"
  grep -q "audit_results=$" "${GITHUB_OUTPUT}"
}

# ---------- Command construction ----------

@test "command: calls octorules audit with correct flags" {
  run bash "${SCRIPT_DIR}/audit.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"audit"* ]]
  [[ "${args}" == *"--config=config.yaml"* ]]
}

@test "command: empty AUDIT_CHECKS does not add --check flag" {
  AUDIT_CHECKS="" run bash "${SCRIPT_DIR}/audit.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" != *"--check"* ]]
}

@test "command: non-empty AUDIT_CHECKS adds --check flags" {
  AUDIT_CHECKS="ip-overlap cdn-ranges" run bash "${SCRIPT_DIR}/audit.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--check ip-overlap --check cdn-ranges"* ]]
}

@test "command: global flags come before subcommand" {
  ZONES="a.com" PHASES="cache_rules" run bash "${SCRIPT_DIR}/audit.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" =~ --config=config\.yaml.*--zone.*--phase.*audit ]]
}

@test "command: zone flags passed correctly" {
  ZONES="a.com b.com" run bash "${SCRIPT_DIR}/audit.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--zone a.com --zone b.com"* ]]
}

@test "command: phase flags passed correctly" {
  PHASES="cache_rules redirect_rules" run bash "${SCRIPT_DIR}/audit.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--phase cache_rules --phase redirect_rules"* ]]
}

@test "command: empty zones and phases produce no flags" {
  ZONES="" PHASES="" run bash "${SCRIPT_DIR}/audit.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" != *"--zone"* ]]
  [[ "${args}" != *"--phase"* ]]
}

# ---------- Exit code handling ----------

@test "exit 0: script exits 0, output shows clean" {
  echo "0" > "${MOCK_EXIT_FILE}"
  run bash "${SCRIPT_DIR}/audit.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"clean"* ]]
  grep -q "audit_exit_code=0" "${GITHUB_OUTPUT}"
}

@test "exit 1: script exits 0, output shows findings" {
  echo "1" > "${MOCK_EXIT_FILE}"
  run bash "${SCRIPT_DIR}/audit.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"findings"* ]]
  grep -q "audit_exit_code=1" "${GITHUB_OUTPUT}"
}

@test "outputs: GITHUB_OUTPUT contains audit_results heredoc" {
  echo "0" > "${MOCK_EXIT_FILE}"
  run bash "${SCRIPT_DIR}/audit.sh"
  [ "${status}" -eq 0 ]
  grep -q "audit_results<<" "${GITHUB_OUTPUT}"
}
