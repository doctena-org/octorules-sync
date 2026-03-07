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
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${CONFIG_PATH:?CONFIG_PATH is not set}"
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is not set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"

require_octorules

# Warn on unexpected input values (don't fail — backwards compat).
warn_unexpected "LINT_SEVERITY" "${LINT_SEVERITY}" "error warning info"

if [ "${LINT}" != "Yes" ]; then
  echo "SKIP: \$LINT is not 'Yes'."
  { echo "lint_exit_code="; echo "lint_results="; } >> "${GITHUB_OUTPUT}"
  exit 0
fi

_lint_resultfile="${GITHUB_WORKSPACE}/octorules-sync.lint"
_lint_logfile="${GITHUB_WORKSPACE}/octorules-sync.lint.log"
_delim="$(random_delim OCTORULES_LINT_EOF)"
rm -f "${_lint_resultfile}" "${_lint_logfile}"

# Build repeated flags from space-separated inputs (populated via nameref in build_flags).
_zone_flags=()
_phase_flags=()
build_flags _zone_flags "--zone" "${ZONES}"
build_flags _phase_flags "--phase" "${PHASES}"

# Global flags before subcommand. Always --exit-code in CI.
_cmd=(octorules --config="${CONFIG_PATH}")
[ ${#_zone_flags[@]} -gt 0 ] && _cmd+=("${_zone_flags[@]}")
[ ${#_phase_flags[@]} -gt 0 ] && _cmd+=("${_phase_flags[@]}")
_cmd+=(lint --exit-code --severity "${LINT_SEVERITY}")

if [ -n "${LINT_PLAN}" ]; then
  _cmd+=(--plan "${LINT_PLAN}")
fi

echo "INFO: Running octorules lint"
run_capturing "${_lint_resultfile}" "${_lint_logfile}" "${_cmd[@]}"

if [ "${_exit_code}" -eq 0 ]; then
  echo "INFO: octorules lint: clean, no issues found."
elif [ "${_exit_code}" -eq 2 ]; then
  echo "WARN: octorules lint found warnings."
else
  echo "FAIL: octorules lint found errors (exit code ${_exit_code})."
fi

# Always exit 0. Store real exit code in output.
{
  echo "lint_exit_code=${_exit_code}"
  echo "lint_results<<${_delim}"
  cat "${_lint_resultfile}"
  echo "${_delim}"
} >> "${GITHUB_OUTPUT}"
