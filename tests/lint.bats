#!/usr/bin/env bats

# Unit tests for scripts/lint.sh
# Uses PATH-override mocking: a temp directory with a fake `octorules`
# script is prepended to $PATH.

setup() {
  export MOCK_DIR="$(mktemp -d)"
  export GITHUB_WORKSPACE="$(mktemp -d)"
  export GITHUB_OUTPUT="$(mktemp)"
  export CONFIG_PATH="config.yaml"
  export LINT="Yes"
  export LINT_SEVERITY="warning"
  export LINT_PLAN=""
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

# ---------- Skip conditions ----------

@test "skip when LINT != Yes" {
  LINT="No" run bash "${SCRIPT_DIR}/lint.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"SKIP"* ]]
}

@test "skip when LINT is empty" {
  LINT="" run bash "${SCRIPT_DIR}/lint.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"SKIP"* ]]
}

@test "skip: outputs empty lint_exit_code and lint_results" {
  LINT="No" run bash "${SCRIPT_DIR}/lint.sh"
  [ "${status}" -eq 0 ]
  grep -q "lint_exit_code=$" "${GITHUB_OUTPUT}"
  grep -q "lint_results=$" "${GITHUB_OUTPUT}"
}

# ---------- Command construction ----------

@test "command: calls octorules lint with correct flags" {
  run bash "${SCRIPT_DIR}/lint.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"lint"* ]]
  [[ "${args}" == *"--config=config.yaml"* ]]
  [[ "${args}" == *"--exit-code"* ]]
  [[ "${args}" == *"--severity warning"* ]]
}

@test "command: empty LINT_PLAN does not add --plan flag" {
  LINT_PLAN="" run bash "${SCRIPT_DIR}/lint.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" != *"--plan"* ]]
}

@test "command: non-empty LINT_PLAN adds --plan flag" {
  LINT_PLAN="business" run bash "${SCRIPT_DIR}/lint.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--plan business"* ]]
}

@test "command: global flags come before subcommand" {
  ZONES="a.com" PHASES="cache_rules" run bash "${SCRIPT_DIR}/lint.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" =~ --config=config\.yaml.*--zone.*--phase.*lint ]]
}

@test "command: zone flags passed correctly" {
  ZONES="a.com b.com" run bash "${SCRIPT_DIR}/lint.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--zone a.com --zone b.com"* ]]
}

@test "command: phase flags passed correctly" {
  PHASES="cache_rules redirect_rules" run bash "${SCRIPT_DIR}/lint.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--phase cache_rules --phase redirect_rules"* ]]
}

@test "command: empty zones and phases produce no flags" {
  ZONES="" PHASES="" run bash "${SCRIPT_DIR}/lint.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" != *"--zone"* ]]
  [[ "${args}" != *"--phase"* ]]
}

@test "command: custom severity" {
  LINT_SEVERITY="error" run bash "${SCRIPT_DIR}/lint.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--severity error"* ]]
}

@test "command: custom plan tier" {
  LINT_PLAN="free" run bash "${SCRIPT_DIR}/lint.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--plan free"* ]]
}

# ---------- Exit code handling ----------

@test "exit 0: succeeds with clean message" {
  echo "0" > "${MOCK_EXIT_FILE}"
  run bash "${SCRIPT_DIR}/lint.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"clean"* ]]
}

@test "exit 1: still exits 0 with FAIL message" {
  echo "1" > "${MOCK_EXIT_FILE}"
  run bash "${SCRIPT_DIR}/lint.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"FAIL"* ]]
}

@test "exit 2: still exits 0 with WARN message" {
  echo "2" > "${MOCK_EXIT_FILE}"
  run bash "${SCRIPT_DIR}/lint.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARN"* ]]
}

# ---------- Outputs ----------

@test "outputs: GITHUB_OUTPUT contains lint_exit_code" {
  echo "1" > "${MOCK_EXIT_FILE}"
  run bash "${SCRIPT_DIR}/lint.sh"
  grep -q "lint_exit_code=1" "${GITHUB_OUTPUT}"
}

@test "outputs: GITHUB_OUTPUT contains lint_results heredoc" {
  run bash "${SCRIPT_DIR}/lint.sh"
  grep -q "lint_results<<OCTORULES_LINT_EOF_" "${GITHUB_OUTPUT}"
}

@test "outputs: lint_results contains octorules stdout" {
  cat > "${MOCK_DIR}/octorules" <<'MOCK'
#!/bin/bash
echo "$@" > "${MOCK_ARGS_FILE}"
echo "some lint output"
exit 2
MOCK
  chmod +x "${MOCK_DIR}/octorules"

  run bash "${SCRIPT_DIR}/lint.sh"
  [ "${status}" -eq 0 ]
  grep -q "some lint output" "${GITHUB_OUTPUT}"
}

# ---------- Files ----------

@test "files: lint results file created in GITHUB_WORKSPACE" {
  run bash "${SCRIPT_DIR}/lint.sh"
  [ -f "${GITHUB_WORKSPACE}/octorules-sync.lint" ]
}

@test "files: old lint files cleaned up before run" {
  echo "stale" > "${GITHUB_WORKSPACE}/octorules-sync.lint"
  echo "stale" > "${GITHUB_WORKSPACE}/octorules-sync.lint.log"
  run bash "${SCRIPT_DIR}/lint.sh"
  [ "${status}" -eq 0 ]
  # File should exist but not contain "stale" (it was recreated by the mock).
  ! grep -q "stale" "${GITHUB_WORKSPACE}/octorules-sync.lint"
}
