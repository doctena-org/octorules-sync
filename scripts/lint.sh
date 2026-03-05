#!/bin/bash
# Run octorules lint (opt-in pre-check before plan/sync).

# Requires these, provided in action.yml:
# - LINT (skip unless "Yes")
# - CONFIG_PATH
# - LINT_SEVERITY
# - LINT_PLAN
# - PHASES
# - ZONES

set -euo pipefail

if [ "${LINT}" != "Yes" ]; then
  echo "SKIP: \$LINT is not 'Yes'."
  { echo "lint_exit_code="; echo "lint_results="; } >> "${GITHUB_OUTPUT}"
  exit 0
fi

_lint_resultfile="${GITHUB_WORKSPACE}/octorules-sync.lint"
_lint_logfile="${GITHUB_WORKSPACE}/octorules-sync.lint.log"
_delim="OCTORULES_LINT_EOF_$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
rm -f "${_lint_resultfile}" "${_lint_logfile}"

# Build repeated flags from space-separated inputs.
_zone_flags=()
if [ -n "${ZONES}" ]; then
  for _z in ${ZONES}; do  # intentional word splitting
    _zone_flags+=("--zone" "${_z}")
  done
fi

_phase_flags=()
if [ -n "${PHASES}" ]; then
  for _p in ${PHASES}; do  # intentional word splitting
    _phase_flags+=("--phase" "${_p}")
  done
fi

# Global flags before subcommand. Always --exit-code in CI.
_cmd=(octorules --config="${CONFIG_PATH}")
[ ${#_zone_flags[@]} -gt 0 ] && _cmd+=("${_zone_flags[@]}")
[ ${#_phase_flags[@]} -gt 0 ] && _cmd+=("${_phase_flags[@]}")
_cmd+=(lint --exit-code --severity "${LINT_SEVERITY}")

if [ -n "${LINT_PLAN}" ]; then
  _cmd+=(--plan "${LINT_PLAN}")
fi

echo "INFO: Running octorules lint"
_exit_code=0
"${_cmd[@]}" 1>"${_lint_resultfile}" 2>"${_lint_logfile}" || _exit_code=$?

_stop_token="stop-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"

if [ "${_exit_code}" -eq 0 ]; then
  echo "INFO: octorules lint: clean, no issues found."
elif [ "${_exit_code}" -eq 2 ]; then
  echo "WARN: octorules lint found warnings."
  echo "::stop-commands::${_stop_token}"
  cat "${_lint_resultfile}"
  echo "::${_stop_token}::"
else
  echo "FAIL: octorules lint found errors (exit code ${_exit_code})."
  echo "::stop-commands::${_stop_token}"
  cat "${_lint_resultfile}"
  cat "${_lint_logfile}"
  echo "::${_stop_token}::"
fi

# Always exit 0. Store real exit code in output.
{
  echo "lint_exit_code=${_exit_code}"
  echo "lint_results<<${_delim}"
  cat "${_lint_resultfile}"
  echo "${_delim}"
} >> "${GITHUB_OUTPUT}"
