#!/bin/bash
# Run octorules audit (opt-in IP-overlap / CDN-range pre-check).

# Requires these, provided in action.yml:
# - AUDIT (skip unless "Yes")
# - CONFIG_PATH
# - AUDIT_CHECKS
# - AUDIT_SEVERITY
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
warn_unexpected "AUDIT_SEVERITY" "${AUDIT_SEVERITY:-}" "error warning info"

if [ "${AUDIT}" != "Yes" ]; then
  echo "SKIP: \$AUDIT is not 'Yes'."
  { echo "audit_exit_code="; echo "audit_results="; } >> "${GITHUB_OUTPUT}"
  exit 0
fi

_audit_resultfile="${GITHUB_WORKSPACE}/octorules-sync.audit"
_audit_logfile="${GITHUB_WORKSPACE}/octorules-sync.audit.log"
_delim="$(random_delim OCTORULES_AUDIT_EOF)"
rm -f "${_audit_resultfile}" "${_audit_logfile}"

# Build repeated flags from space-separated inputs (populated via nameref in build_flags).
_zone_flags=()
_phase_flags=()
build_flags _zone_flags "--zone" "${ZONES}"
build_flags _phase_flags "--phase" "${PHASES}"

# Global flags before subcommand. Always --exit-code in CI.
_cmd=(octorules --config="${CONFIG_PATH}")
[ ${#_zone_flags[@]} -gt 0 ] && _cmd+=("${_zone_flags[@]}")
[ ${#_phase_flags[@]} -gt 0 ] && _cmd+=("${_phase_flags[@]}")
_audit_severity="${AUDIT_SEVERITY:-warning}"
_cmd+=(audit --exit-code --severity "${_audit_severity}")

# Optional --check filters.
_audit_checks="${AUDIT_CHECKS:-}"
if [ -n "${_audit_checks}" ]; then
  for _chk in ${_audit_checks}; do  # intentional word splitting
    _cmd+=(--check "${_chk}")
  done
fi

echo "INFO: Running octorules audit"
run_capturing "${_audit_resultfile}" "${_audit_logfile}" "${_cmd[@]}"

if [ "${_exit_code}" -eq 0 ]; then
  echo "INFO: octorules audit: clean, no findings."
elif [ "${_exit_code}" -eq 2 ]; then
  echo "WARN: octorules audit found warnings."
else
  echo "FAIL: octorules audit found errors (exit code ${_exit_code})."
fi

# Always exit 0. Store real exit code in output.
{
  echo "audit_exit_code=${_exit_code}"
  echo "audit_results<<${_delim}"
  cat "${_audit_resultfile}"
  echo "${_delim}"
} >> "${GITHUB_OUTPUT}"
