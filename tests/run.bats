#!/usr/bin/env bats

# Unit tests for scripts/run.sh
# Uses PATH-override mocking: a temp directory with a fake `octorules`
# script is prepended to $PATH.

setup() {
  export MOCK_DIR="$(mktemp -d)"
  export GITHUB_WORKSPACE="$(mktemp -d)"
  export GITHUB_OUTPUT="$(mktemp)"
  export CONFIG_PATH="config.yaml"
  export DOIT=""
  export FORCE="No"
  export CHECKSUM=""
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

# ---------- Plan mode ----------

@test "plan mode: calls octorules plan with --config and --checksum" {
  DOIT="" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"plan"* ]]
  [[ "${args}" == *"--config=config.yaml"* ]]
  [[ "${args}" == *"--checksum"* ]]
  [[ "${args}" != *"--doit"* ]]
  [[ "${args}" != *"--format"* ]]
}

@test "plan mode exit 0: succeeds with no changes message" {
  echo "0" > "${MOCK_EXIT_FILE}"
  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"No changes detected"* ]]
}

@test "plan mode exit 2: succeeds with changes detected message" {
  echo "2" > "${MOCK_EXIT_FILE}"
  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"detected changes"* ]]
}

@test "plan mode exit 1: fails with FAIL message" {
  echo "1" > "${MOCK_EXIT_FILE}"
  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL"* ]]
}

# ---------- Sync mode ----------

@test "sync mode: calls octorules sync --doit with correct flags" {
  DOIT="--doit" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"sync"* ]]
  [[ "${args}" == *"--doit"* ]]
  [[ "${args}" == *"--config=config.yaml"* ]]
  [[ "${args}" != *"--format"* ]]
}

@test "sync mode with --force: includes --force when FORCE=Yes" {
  DOIT="--doit" FORCE="Yes" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--force"* ]]
}

@test "sync mode with checksum: includes --checksum HASH" {
  DOIT="--doit" CHECKSUM="abc123" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--checksum abc123"* ]]
}

# ---------- Zone & phase flags ----------

@test "zone flags: ZONES produces --zone flags" {
  ZONES="a.com b.com" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--zone a.com --zone b.com"* ]]
}

@test "phase flags: PHASES produces --phase flags" {
  PHASES="cache_rules redirect_rules" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--phase cache_rules --phase redirect_rules"* ]]
}

@test "empty zones and phases: no --zone or --phase flags" {
  ZONES="" PHASES="" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" != *"--zone"* ]]
  [[ "${args}" != *"--phase"* ]]
}

# ---------- Outputs ----------

@test "outputs: GITHUB_OUTPUT contains exit_code" {
  run bash "${SCRIPT_DIR}/run.sh"
  grep -q "exit_code=" "${GITHUB_OUTPUT}"
}

@test "outputs: GITHUB_OUTPUT contains plan heredoc" {
  run bash "${SCRIPT_DIR}/run.sh"
  grep -q "plan<<OCTORULES_EOF" "${GITHUB_OUTPUT}"
}

@test "outputs: GITHUB_OUTPUT contains log heredoc" {
  run bash "${SCRIPT_DIR}/run.sh"
  grep -q "log<<OCTORULES_EOF" "${GITHUB_OUTPUT}"
}

# ---------- Failure output ----------

@test "failure output: log and plan file contents appear on error" {
  # Make mock write output to stderr/stdout so the files have content.
  cat > "${MOCK_DIR}/octorules" <<'MOCK'
#!/bin/bash
echo "$@" > "${MOCK_ARGS_FILE}"
echo "plan output here" >&1
echo "log output here" >&2
exit "$(cat "${MOCK_EXIT_FILE}")"
MOCK
  chmod +x "${MOCK_DIR}/octorules"

  echo "1" > "${MOCK_EXIT_FILE}"
  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL"* ]]
  [[ "${output}" == *"Log output"* ]] || [[ "${output}" == *"log output"* ]] || [[ "${output}" == *"Plan output"* ]] || [[ "${output}" == *"plan output"* ]]
}

# ---------- Checksum output ----------

@test "plan mode: GITHUB_OUTPUT contains checksum when octorules emits it" {
  # Mock writes a checksum line to stderr (the logfile).
  cat > "${MOCK_DIR}/octorules" <<'MOCK'
#!/bin/bash
echo "$@" > "${MOCK_ARGS_FILE}"
echo "checksum=abc123def456" >&2
exit 0
MOCK
  chmod +x "${MOCK_DIR}/octorules"

  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 0 ]
  grep -q "checksum=abc123def456" "${GITHUB_OUTPUT}"
}

@test "plan mode: GITHUB_OUTPUT contains empty checksum when octorules does not emit it" {
  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 0 ]
  grep -q "checksum=$" "${GITHUB_OUTPUT}"
}

@test "sync mode: does not pass --checksum when CHECKSUM is empty" {
  DOIT="--doit" CHECKSUM="" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" != *"--checksum"* ]]
}
