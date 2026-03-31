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
  export AUDIT_LOG=""

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
  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"CONFIG_PATH"* ]]
}

@test "fails when GITHUB_WORKSPACE unset" {
  unset GITHUB_WORKSPACE
  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"GITHUB_WORKSPACE"* ]]
}

@test "fails when GITHUB_OUTPUT unset" {
  unset GITHUB_OUTPUT
  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"GITHUB_OUTPUT"* ]]
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

@test "plan mode: global flags come before subcommand" {
  DOIT="" ZONES="a.com" PHASES="cache_rules" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  # --config, --zone, --phase must appear before "plan"
  [[ "${args}" =~ --config=config\.yaml.*--zone.*--phase.*plan ]]
}

@test "sync mode: global flags come before subcommand" {
  DOIT="--doit" ZONES="a.com" PHASES="cache_rules" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  # --config, --zone, --phase must appear before "sync"
  [[ "${args}" =~ --config=config\.yaml.*--zone.*--phase.*sync ]]
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

@test "sync mode without --force: omits --force when FORCE=No" {
  DOIT="--doit" FORCE="No" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" != *"--force"* ]]
}

@test "sync mode with checksum: includes --checksum HASH" {
  DOIT="--doit" CHECKSUM="abc123" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--checksum abc123"* ]]
}

# ---------- Audit log ----------

@test "sync mode with audit log: includes --audit-log PATH" {
  DOIT="--doit" AUDIT_LOG="/tmp/audit.jsonl" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" == *"--audit-log /tmp/audit.jsonl"* ]]
}

@test "sync mode without audit log: omits --audit-log when empty" {
  DOIT="--doit" AUDIT_LOG="" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" != *"--audit-log"* ]]
}

@test "plan mode: does not pass --audit-log" {
  AUDIT_LOG="/tmp/audit.jsonl" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" != *"--audit-log"* ]]
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
  grep -q "plan<<OCTORULES_EOF_" "${GITHUB_OUTPUT}"
}

@test "outputs: GITHUB_OUTPUT contains log heredoc" {
  run bash "${SCRIPT_DIR}/run.sh"
  grep -q "log<<OCTORULES_EOF_" "${GITHUB_OUTPUT}"
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
  # Mock writes a 64-char hex checksum line to stderr (the logfile).
  # Must be exactly 64 hex chars — run.sh extracts only SHA-256 length checksums.
  _mock_checksum="a1b2c3d4e5f67890a1b2c3d4e5f67890a1b2c3d4e5f67890a1b2c3d4e5f67890"
  cat > "${MOCK_DIR}/octorules" <<MOCK
#!/bin/bash
echo "\$@" > "\${MOCK_ARGS_FILE}"
echo "checksum=${_mock_checksum}" >&2
exit 0
MOCK
  chmod +x "${MOCK_DIR}/octorules"

  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 0 ]
  # Verify the checksum appears as an output variable line, not inside the log heredoc.
  grep -q "^checksum=${_mock_checksum}$" "${GITHUB_OUTPUT}"
}

@test "plan mode: GITHUB_OUTPUT contains empty checksum when octorules does not emit it" {
  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 0 ]
  grep -q "checksum=$" "${GITHUB_OUTPUT}"
}

@test "plan mode failure: GITHUB_OUTPUT has no checksum line" {
  echo "1" > "${MOCK_EXIT_FILE}"
  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 1 ]
  # Error paths should not include a checksum= line in GITHUB_OUTPUT.
  ! grep -q "^checksum=" "${GITHUB_OUTPUT}"
}

@test "sync mode failure: GITHUB_OUTPUT has no checksum line" {
  echo "1" > "${MOCK_EXIT_FILE}"
  DOIT="--doit" run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 1 ]
  ! grep -q "^checksum=" "${GITHUB_OUTPUT}"
}

@test "sync mode success: GITHUB_OUTPUT still has checksum line" {
  DOIT="--doit" run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 0 ]
  # Success path always writes checksum= (empty for sync mode).
  grep -q "^checksum=$" "${GITHUB_OUTPUT}"
}

@test "sync mode: does not pass --checksum when CHECKSUM is empty" {
  DOIT="--doit" CHECKSUM="" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  [[ "${args}" != *"--checksum"* ]]
}

# ---------- Empty output ----------

@test "empty output: plan heredoc handles empty plan file" {
  # Mock produces no stdout (empty plan file).
  cat > "${MOCK_DIR}/octorules" <<'MOCK'
#!/bin/bash
echo "$@" > "${MOCK_ARGS_FILE}"
exit 0
MOCK
  chmod +x "${MOCK_DIR}/octorules"

  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 0 ]
  # GITHUB_OUTPUT should still contain plan heredoc (even if empty content).
  grep -q "plan<<OCTORULES_EOF_" "${GITHUB_OUTPUT}"
}

@test "html plan file preferred over text plan for PR comments" {
  # Mock produces text stdout, and separately an HTML file is present.
  cat > "${MOCK_DIR}/octorules" <<'MOCK'
#!/bin/bash
echo "$@" > "${MOCK_ARGS_FILE}"
echo "text plan output"
# Simulate PlanHtml writing an HTML file via path: config
echo "<h2>html plan</h2>" > "${GITHUB_WORKSPACE}/octorules-plan.html"
exit 0
MOCK
  chmod +x "${MOCK_DIR}/octorules"

  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 0 ]
  # plan output should contain the HTML, not the text
  grep -q "<h2>html plan</h2>" "${GITHUB_OUTPUT}"
  # text should NOT be in the plan output (it went to stdout/terminal only)
  ! grep -q "text plan output" <(grep -A1 "plan<<" "${GITHUB_OUTPUT}")
}

@test "text plan used when no html file exists" {
  cat > "${MOCK_DIR}/octorules" <<'MOCK'
#!/bin/bash
echo "$@" > "${MOCK_ARGS_FILE}"
echo "text plan output"
exit 0
MOCK
  chmod +x "${MOCK_DIR}/octorules"

  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 0 ]
  # No HTML file, so plan output should be the captured text
  grep -q "text plan output" "${GITHUB_OUTPUT}"
}

@test "empty output: log heredoc handles empty log file" {
  cat > "${MOCK_DIR}/octorules" <<'MOCK'
#!/bin/bash
echo "$@" > "${MOCK_ARGS_FILE}"
exit 0
MOCK
  chmod +x "${MOCK_DIR}/octorules"

  run bash "${SCRIPT_DIR}/run.sh"
  [ "${status}" -eq 0 ]
  grep -q "log<<OCTORULES_EOF_" "${GITHUB_OUTPUT}"
}
