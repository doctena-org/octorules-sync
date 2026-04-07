#!/usr/bin/env bats

# Shell injection / adversarial input tests.
# Validates that special characters in inputs do not cause shell injection,
# argument splitting, or glob expansion.

setup() {
  export MOCK_DIR="$(mktemp -d)"
  export GITHUB_WORKSPACE="$(mktemp -d)"
  export GITHUB_OUTPUT="$(mktemp)"
  export DOIT=""
  export FORCE=""
  export CHECKSUM=""
  export PHASES=""
  export ZONES=""
  export AUDIT_LOG=""

  # Create a dummy config file so the existence check passes.
  touch "${GITHUB_WORKSPACE}/config.yaml"
  export CONFIG_PATH="${GITHUB_WORKSPACE}/config.yaml"

  export MOCK_ARGS_FILE="${MOCK_DIR}/octorules.args"
  export MOCK_EXIT_FILE="${MOCK_DIR}/octorules.exit"
  echo "0" > "${MOCK_EXIT_FILE}"

  # Mock octorules that writes each argument on its own line.
  # Using one-arg-per-line makes it possible to verify exact values.
  cat > "${MOCK_DIR}/octorules" <<'MOCK'
#!/bin/bash
for arg in "$@"; do
  echo "${arg}"
done > "${MOCK_ARGS_FILE}"
exit "$(cat "${MOCK_EXIT_FILE}")"
MOCK
  chmod +x "${MOCK_DIR}/octorules"

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
  rm -rf "${MOCK_DIR}" "${GITHUB_WORKSPACE}" "${GITHUB_OUTPUT}"
}

# ---------- build_flags: adversarial values ----------

@test "build_flags: value with backticks is treated as literal" {
  build_flags my_arr "--zone" '`whoami`.com'
  [ "${#my_arr[@]}" -eq 2 ]
  [ "${my_arr[0]}" = "--zone" ]
  [ "${my_arr[1]}" = '`whoami`.com' ]
}

@test "build_flags: value with dollar-paren is treated as literal" {
  build_flags my_arr "--zone" '$(id).com'
  [ "${#my_arr[@]}" -eq 2 ]
  [ "${my_arr[1]}" = '$(id).com' ]
}

@test "build_flags: semicolons within a word are treated as literal" {
  # build_flags word-splits on spaces (by design), but shell metacharacters
  # within each word must remain literal — no command injection.
  build_flags my_arr "--zone" 'a.com;rm'
  [ "${#my_arr[@]}" -eq 2 ]
  [ "${my_arr[1]}" = 'a.com;rm' ]
}

@test "build_flags: pipe within a word is treated as literal" {
  build_flags my_arr "--phase" 'cache_rules|cat'
  [ "${#my_arr[@]}" -eq 2 ]
  [ "${my_arr[1]}" = 'cache_rules|cat' ]
}

@test "build_flags: value with double quotes is treated as literal" {
  build_flags my_arr "--zone" '"quoted.com"'
  [ "${#my_arr[@]}" -eq 2 ]
  [ "${my_arr[1]}" = '"quoted.com"' ]
}

@test "build_flags: value with single quotes is treated as literal" {
  build_flags my_arr "--zone" "it's.com"
  [ "${#my_arr[@]}" -eq 2 ]
  [ "${my_arr[1]}" = "it's.com" ]
}

# ---------- run.sh: CONFIG_PATH with spaces ----------

@test "run.sh: CONFIG_PATH with spaces is passed correctly" {
  mkdir -p "${GITHUB_WORKSPACE}/path with spaces"
  touch "${GITHUB_WORKSPACE}/path with spaces/config.yaml"
  CONFIG_PATH="${GITHUB_WORKSPACE}/path with spaces/config.yaml" run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  # The --config value should include the full path with spaces.
  [[ "${args}" == *"--config=${GITHUB_WORKSPACE}/path with spaces/config.yaml"* ]]
}

# ---------- run.sh: ZONES with shell metacharacters ----------

@test "run.sh: ZONES with backticks passed as literal" {
  ZONES='`whoami`.com' run bash "${SCRIPT_DIR}/run.sh"
  args="$(cat "${MOCK_ARGS_FILE}")"
  # The zone value should be the literal backtick string.
  grep -qF '`whoami`.com' "${MOCK_ARGS_FILE}"
}

@test "run.sh: ZONES with dollar-paren passed as literal" {
  ZONES='$(id).com' run bash "${SCRIPT_DIR}/run.sh"
  grep -qF '$(id).com' "${MOCK_ARGS_FILE}"
}

@test "run.sh: PHASES with semicolons within a word passed as literal" {
  PHASES='cache_rules;drop' run bash "${SCRIPT_DIR}/run.sh"
  grep -qF 'cache_rules;drop' "${MOCK_ARGS_FILE}"
}

# ---------- run.sh: CHECKSUM with injection attempts ----------

@test "run.sh: CHECKSUM with semicolons passed as literal" {
  DOIT="--doit" CHECKSUM='abc;rm -rf /' run bash "${SCRIPT_DIR}/run.sh"
  grep -qF 'abc;rm -rf /' "${MOCK_ARGS_FILE}"
}

@test "run.sh: CHECKSUM with backticks passed as literal" {
  DOIT="--doit" CHECKSUM='abc`id`def' run bash "${SCRIPT_DIR}/run.sh"
  grep -qF 'abc`id`def' "${MOCK_ARGS_FILE}"
}

# ---------- run.sh: AUDIT_LOG with special characters ----------

@test "run.sh: AUDIT_LOG with spaces passed correctly" {
  DOIT="--doit" AUDIT_LOG="/tmp/my audit log.jsonl" run bash "${SCRIPT_DIR}/run.sh"
  grep -qF '/tmp/my audit log.jsonl' "${MOCK_ARGS_FILE}"
}

# ---------- run_capturing: special characters in command ----------

@test "run_capturing: captures output from command with quoted args" {
  local out_file="${MOCK_DIR}/out.log"
  local err_file="${MOCK_DIR}/err.log"
  run_capturing "${out_file}" "${err_file}" echo "hello 'world' \$(not-a-cmd)"
  [ "${_exit_code}" -eq 0 ]
  [[ "$(cat "${out_file}")" == *'$(not-a-cmd)'* ]]
}

# ---------- warn_unexpected: special characters ----------

@test "warn_unexpected: value with backticks does not execute" {
  run warn_unexpected "TEST" '`whoami`' "Yes No"
  [ "${status}" -eq 0 ]
  # Output should contain the literal backtick string, not a username.
  [[ "${output}" == *'`whoami`'* ]]
}

@test "warn_unexpected: value with dollar-paren does not execute" {
  run warn_unexpected "TEST" '$(id)' "Yes No"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'$(id)'* ]]
}

# ---------- retry: command with special characters ----------

@test "retry: command argument with spaces preserved" {
  result="$(retry 3 1 echo "hello world")"
  [ "${result}" = "hello world" ]
}

# ---------- audit.sh: AUDIT_CHECKS with shell metacharacters ----------

@test "audit.sh: AUDIT_CHECKS with backticks passed as literal" {
  AUDIT="Yes" AUDIT_CHECKS='ip-overlap `whoami`' AUDIT_SEVERITY="warning" run bash "${SCRIPT_DIR}/audit.sh"
  grep -qF '`whoami`' "${MOCK_ARGS_FILE}"
}

@test "audit.sh: AUDIT_CHECKS with dollar-paren passed as literal" {
  AUDIT="Yes" AUDIT_CHECKS='ip-overlap $(id)' AUDIT_SEVERITY="warning" run bash "${SCRIPT_DIR}/audit.sh"
  grep -qF '$(id)' "${MOCK_ARGS_FILE}"
}

# ---------- lint.sh: LINT_PLAN with spaces ----------

@test "lint.sh: LINT_PLAN with spaces passed as single argument" {
  LINT="Yes" LINT_PLAN="free plan" LINT_SEVERITY="warning" run bash "${SCRIPT_DIR}/lint.sh"
  grep -qF 'free plan' "${MOCK_ARGS_FILE}"
}
