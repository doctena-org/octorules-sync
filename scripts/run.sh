#!/bin/bash
# Run octorules plan or sync

# Requires these, provided in action.yml:
# - CONFIG_PATH
# - DOIT
# - FORCE
# - CHECKSUM
# - PHASES
# - ZONES
# - AUDIT_LOG (optional)

set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${CONFIG_PATH:?CONFIG_PATH is not set}"
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is not set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"

require_octorules

_config_path="${CONFIG_PATH}"
_doit="${DOIT}"
_force="${FORCE}"
_checksum="${CHECKSUM}"
_phases="${PHASES}"
_zones="${ZONES}"

# Strict validation of action inputs to prevent silent plan-instead-of-sync.
if [ -n "${_doit}" ] && [ "${_doit}" != "--doit" ]; then
  echo "FAIL: \$DOIT must be empty or '--doit' (got '${_doit}')"
  exit 1
fi
if [ -n "${_force}" ] && [ "${_force}" != "Yes" ]; then
  echo "FAIL: \$FORCE must be empty or 'Yes' (got '${_force}')"
  exit 1
fi

# Validate config file exists before running octorules.
if [ ! -f "${_config_path}" ]; then
  echo "FAIL: config file not found: ${_config_path}"
  exit 1
fi

# Output files.
_logfile="${GITHUB_WORKSPACE}/octorules-sync.log"
_planfile="${GITHUB_WORKSPACE}/octorules-sync.plan"
# HTML plan file: written by PlanHtml with path: in octorules config.
# Preferred over _planfile for PR comments (renders tables in GitHub markdown).
_htmlfile="${GITHUB_WORKSPACE}/octorules-plan.html"
_delim="$(random_delim OCTORULES_EOF)"
_checksum_value=""

echo "INFO: Cleaning up plan and log files if they already exist"
rm -f "${_logfile}" "${_planfile}" "${_htmlfile}"
touch "${_logfile}" "${_planfile}"

echo "INFO: config_path: ${_config_path}"

# Build repeated flags from space-separated inputs (populated via nameref in build_flags).
_zone_flags=()
_phase_flags=()
build_flags _zone_flags "--zone" "${_zones}"
build_flags _phase_flags "--phase" "${_phases}"

# Write GITHUB_OUTPUT variables. Called on both success and failure paths.
# Pass "with_checksum" to include the checksum line (success path only).
# For the "plan" output: prefer the HTML file (renders tables in PR comments),
# fall back to the captured stdout (text plan).
_write_outputs() {
  local _plan_source="${_planfile}"
  if [ -s "${_htmlfile}" ]; then
    _plan_source="${_htmlfile}"
  fi
  {
    echo "exit_code=${_exit_code}"
    if [ "${1:-}" = "with_checksum" ]; then
      echo "checksum=${_checksum_value}"
    fi
    echo "log<<${_delim}"
    cat "${_logfile}"
    echo "${_delim}"
    echo "plan<<${_delim}"
    cat "${_plan_source}"
    echo "${_delim}"
  } >> "${GITHUB_OUTPUT}"
}

if [ "${_doit}" = "--doit" ]; then
  # --- Apply mode: octorules sync --doit ---
  # Global flags (--config, --zone, --phase) must come before the subcommand.
  _cmd=(octorules --config="${_config_path}")
  [ ${#_zone_flags[@]} -gt 0 ] && _cmd+=("${_zone_flags[@]}")
  [ ${#_phase_flags[@]} -gt 0 ] && _cmd+=("${_phase_flags[@]}")
  _cmd+=(sync --doit)

  if [ "${_force}" = "Yes" ]; then
    echo "INFO: Running octorules sync with --force"
    _cmd+=(--force)
  fi

  if [ -n "${_checksum}" ]; then
    echo "INFO: Using checksum: ${_checksum}"
    _cmd+=(--checksum "${_checksum}")
  fi

  _audit_log="${AUDIT_LOG:-}"
  if [ -n "${_audit_log}" ]; then
    echo "INFO: Audit log: ${_audit_log}"
    _cmd+=(--audit-log "${_audit_log}")
  fi

  echo "INFO: Running octorules sync --doit"
  run_capturing "${_planfile}" "${_logfile}" "${_cmd[@]}"

  if [ "${_exit_code}" -ne 0 ]; then
    echo "FAIL: octorules sync exited with code ${_exit_code}."
    _write_outputs
    exit 1
  fi
else
  # --- Plan mode: octorules plan ---
  # Global flags (--config, --zone, --phase) must come before the subcommand.
  _cmd=(octorules --config="${_config_path}")
  [ ${#_zone_flags[@]} -gt 0 ] && _cmd+=("${_zone_flags[@]}")
  [ ${#_phase_flags[@]} -gt 0 ] && _cmd+=("${_phase_flags[@]}")
  _cmd+=(plan --checksum)

  echo "INFO: Running octorules plan"
  run_capturing "${_planfile}" "${_logfile}" "${_cmd[@]}"

  if [ "${_exit_code}" -eq 0 ]; then
    echo "INFO: octorules plan completed. No changes detected."
  elif [ "${_exit_code}" -eq 2 ]; then
    echo "INFO: octorules plan detected changes."
  else
    echo "FAIL: octorules plan exited with code ${_exit_code}."
    _write_outputs
    exit 1
  fi
fi

echo "INFO: octorules output has been written to ${_logfile}"

# Extract checksum from plan logfile (plan mode only).
# Accepts 32-128 hex chars to be forward-compatible with hash algorithm changes.
if [ "${_doit}" != "--doit" ] && [ -f "${_logfile}" ]; then
  _checksum_value="$(grep -oP '^checksum=\K[0-9a-f]{32,128}' "${_logfile}" || true)"
fi

_write_outputs with_checksum
