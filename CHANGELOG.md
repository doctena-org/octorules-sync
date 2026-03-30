# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.7.0] - 2026-03-30

### Added
- `audit_severity` input: minimum severity for audit findings (default: `warning`).
- Integration test for audit warnings allowing sync to proceed (exit code 2).

### Changed
- Audit step now passes `--exit-code` and `--severity` flags to `octorules audit`,
  mirroring the lint step behavior.
- Sync guard updated: audit exit code 2 (warnings only) no longer blocks sync.
  Only exit code 1 (errors) prevents deployment.
- "Fail on audit findings" step renamed to "Fail on audit errors" for clarity.

## [1.6.2] - 2026-03-30

### Added
- `audit` input: opt-in `octorules audit` pre-check (IP overlap, CDN range,
  zone drift analysis) before plan/sync, with `audit_checks` filter.
- `audit_exit_code` and `audit_results` outputs.
- `scripts/audit.sh` with BATS test coverage.

### Changed
- Sync lint guard changed from blacklist (`!= '1'`) to whitelist
  (`== '' || == '0' || == '2'`); unexpected exit codes now block sync.
- Audit findings now gate sync in `--doit` mode (same as lint errors).
  Plan mode always runs regardless of audit results.

## [1.6.1] - 2026-03-24

### Changed
- Release workflow now gated on CI (lint + test) via `workflow_call`, matching
  all other repos in the ecosystem.

### Added
- Adversarial input BATS tests: validate that shell metacharacters (backticks,
  `$(...)`, semicolons, pipes, quotes) in `ZONES`, `PHASES`, `CHECKSUM`,
  `CONFIG_PATH`, and `AUDIT_LOG` are treated as literals, not executed.

## [1.6.0] - 2026-03-23

### Added
- `audit_log` input: pass `--audit-log PATH` to `octorules sync` for structured
  JSON-lines audit trail of sync results.
- Validate `PR_NUMBER` is numeric before calling GitHub API in `comment.sh`.

### Changed
- Provider-agnostic error message when `octorules` is not found on PATH. Lists
  install commands for all three providers (Cloudflare, AWS, Google).

## [1.5.0] - 2026-03-18

### Fixed
- PR comments now use HTML plan file when available. Previously only the
  GITHUB_OUTPUT `plan` variable used the HTML file; `comment.sh` read the
  raw plan file (text) directly. Now both paths prefer the HTML file.

### Changed
- Standardize workflow extensions from `.yml` to `.yaml`.
- README: multi-provider examples, provider-specific install commands,
  updated troubleshooting and `lint_plan` description.

## [1.4.0] - 2026-03-17

### Added
- HTML plan file support: when octorules writes an HTML plan file via
  `PlanHtml` with `path:` config, the action uses it for PR comments
  (renders tables). Text output goes to stdout for readable terminal logs.
  Falls back to captured stdout when no HTML file exists (backward compatible).

## [1.3.1] - 2026-03-14

### Fixed
- `comment.sh`: handle `git log` returning empty output (e.g. empty repo)
  by falling back to "unknown" commit SHA.
- `action.yml`: "Fail on lint errors" step now explicitly checks
  `inputs.lint == 'Yes'`, making the guard future-proof instead of relying
  on empty-string comparison.

## [1.3.0] - 2026-03-07

### Added
- `require_octorules()` helper in `lib.sh` — fails with a clear message
  if octorules is not found on PATH. Used by `run.sh` and `lint.sh`.
- `run_capturing()` helper in `lib.sh` — centralizes the `tee` + `wait` +
  `sync` pattern for capturing stdout/stderr to files.
- `warn_unexpected()` helper in `lib.sh` — warns (without failing) when
  an input value is not in the expected set. Used for `DOIT`, `FORCE`, and
  `LINT_SEVERITY` validation.
- `comment.sh` now distinguishes empty plan file ("No changes detected") from
  missing plan file ("No plan output — run step was skipped").
- `run.sh` touches plan/log files after cleanup to guarantee they exist even
  if octorules never runs.
- `run.sh` and `lint.sh` call `sync` after `wait` to flush kernel buffers
  before reading output files.
- Release workflow validates tag matches `^vX.Y.Z$` semver format before
  creating a release.
- Integration tests: exit-code-2 (changes detected) and lint-errors-block-sync
  scenarios.
- README: troubleshooting section (octorules not found, CF token, config,
  PR comment permissions).
- README: documents `<!-- octorules-sync-plan -->` comment deduplication marker.
- README: clarifies `pr_comment_token` requires explicit token (not auto-injected).
- `lib.bats`: tests for `require_octorules`, `run_capturing`, `warn_unexpected`.
- `comment.bats`: test for empty plan file vs missing plan file.

### Removed
- `escape_actions_tags()` from `lib.sh` — was dead code (defined and tested
  but never called from any script). Test removed from `lib.bats`.

### Changed
- `run.sh` and `lint.sh` use `require_octorules` and `run_capturing` from
  `lib.sh` instead of inline duplicates.
- Install message recommends `octorules[wirefilter]` instead of bare
  `octorules`.

## [1.2.5] - 2026-03-07

### Fixed

- **Comment deduplication broken since v1.2.3**: the `--arg` jq flag doesn't
  work with `gh api --jq` (which takes a single expression string, not
  separate jq flags). The comment lookup always failed silently, causing a
  new comment on every run instead of updating the existing one. Fixed by
  inlining the marker constant in the jq expression.

## [1.2.4] - 2026-03-07

### Fixed

- PR comment now includes a `### Rule Changes` header above the plan output.
  Previously the plan content appeared as an orphaned line between horizontal
  rules with no section header, making the comment look broken.

## [1.2.3] - 2026-03-07

### Security

- `comment.sh`: jq filter used `--arg` for the marker variable instead of
  shell interpolation — **reverted in v1.2.4** (`--arg` is not supported by
  `gh api --jq`, broke comment deduplication).
- `run.sh`: added `${CONFIG_PATH:?}`, `${GITHUB_WORKSPACE:?}`, `${GITHUB_OUTPUT:?}`
  validation — fails fast with a clear message if required env vars are unset.
- `lint.sh`: added `${CONFIG_PATH:?}`, `${GITHUB_WORKSPACE:?}`, and
  `${GITHUB_OUTPUT:?}` validation.
- `comment.sh`: added `${GITHUB_WORKSPACE:?}` validation.

### Added

- Env var validation tests in `run.bats` (3 tests: CONFIG_PATH, GITHUB_WORKSPACE,
  GITHUB_OUTPUT unset).
- Env var validation tests in `lint.bats` (3 tests: CONFIG_PATH, GITHUB_WORKSPACE,
  GITHUB_OUTPUT unset).

## [1.2.2] - 2026-03-06

### Changed

- Extracted `build_flags()` and `escape_actions_tags()` into `lib.sh` — removes
  duplicate flag-building loops from `run.sh` and `lint.sh`, and deduplicates
  the inline `sed` command for escaping GitHub Actions log annotations.
- Extracted `_write_outputs()` function in `run.sh` — deduplicates the
  GITHUB_OUTPUT heredoc block (was repeated 3 times). Error paths no longer
  emit a `checksum=` line (only success paths do).
- Checksum extraction regex tightened from `[0-9a-f]+` to `[0-9a-f]{64}`
  (SHA-256 is always exactly 64 hex chars).
- CI: `yamllint` install pinned to `>=1.35,<2` instead of unpinned `pip install
  yamllint`.
- Release workflow validates major version tag format before force-pushing
  (rejects malformed tags like `v1.2` → `v1` extraction failures).

### Added

- `build_flags` tests in `lib.bats` (3 tests: multi-value, empty, single).
- `escape_actions_tags` test in `lib.bats` (verifies stdout output and file
  preservation).
- `comment lookup fails after max retries exhausted` test in `comment.bats`.
- Checksum output tests in `run.bats`: error paths have no `checksum=` line,
  success paths always have `checksum=` line.

## [1.2.1] - 2026-03-06

### Fixed

- PR comment now shows "Lint: clean, no issues found." when lint is enabled
  and passes with no findings. Previously, the lint section was omitted
  entirely when clean, requiring reviewers to check CI logs.
- CI workflow installs `yamllint` explicitly via pip instead of relying on
  it being pre-installed on the GitHub runner.

## [1.2.0] - 2026-03-05

### Added

- `random_delim()` function in `lib.sh` — centralizes random heredoc delimiter
  generation (was duplicated in `run.sh` and `lint.sh`)
- Integration test workflow (`.github/workflows/integration.yml`) — end-to-end
  test of the composite action with a mock `octorules` binary
- Empty output tests for `run.bats` and `lint.bats` — verifies GITHUB_OUTPUT
  heredoc handles empty plan/lint content correctly
- `random_delim` tests in `lib.bats`
- Git log fallback test in `comment.bats`
- Token scope documentation for `pr_comment_token` in README

### Fixed

- `comment.sh`: `git log` failure (e.g. shallow clone, missing git) now
  falls back to `_sha="unknown"` instead of aborting
- `action.yml`: comment and fail-on-lint steps use `!cancelled()` instead of
  `always()` — prevents running after workflow cancellation
- `comment.sh`: added `shellcheck source` directive for `lib.sh`
- `run.sh` and `lint.sh`: source `lib.sh` and use `random_delim()` instead
  of inline delimiter generation

## [1.1.2] - 2026-03-05

### Fixed

- Lint output `[WARNING]` and `[ERROR]` tags mangled in GitHub Actions logs
  (Actions interpreted them as workflow commands); also fixes missing newlines
  caused by the `stop-commands` approach in v1.1.1

## [1.1.1] - 2026-03-05

### Fixed

- Lint output `[WARNING]` and `[ERROR]` tags mangled in GitHub Actions logs
  (Actions interpreted them as workflow commands)

## [1.1.0] - 2026-03-05

### Added

- `lint`, `lint_severity`, and `lint_plan` inputs for opt-in pre-check linting
- `lint_exit_code` and `lint_results` outputs
- Lint results section in PR plan comments when lint finds issues
- Lint errors gate sync mode (prevent applying changes with lint errors)
- Wirefilter support section in README explaining why `octorules[wirefilter]`
  is recommended for lint workflows

### Fixed

- `required: true` removed from inputs with defaults (`config_path`,
  `add_pr_comment`, `pr_comment_token`) — contradicted by having a default
- Shell scripts hardened with `set -euo pipefail`; non-zero exits from
  octorules are captured explicitly
- README examples updated to pin `@v1` instead of `@main`
- README lint examples use `octorules[wirefilter]>=0.11,<2` for authoritative
  expression validation
- `pr_comment_token` default changed from `"Not set"` to `""` (empty string)

### Security

- Pin 3rd-party GitHub Actions to commit SHAs (Aikido finding):
  `bats-core/bats-action` pinned to SHA; GitHub-owned actions (`actions/checkout`)
  use version tags
- GITHUB_OUTPUT heredoc delimiter injection: replaced fixed `OCTORULES_EOF`
  with randomized delimiter to prevent output spoofing
- GitHub Actions command injection: `release.yml` and
  `update-major-version.yml` now pass tag names via `env:` instead of
  inline `${{ }}` in `run:` blocks
- Empty array expansion: fixed `"${array[@]}"` under `set -u` when array
  is empty in `run.sh`
- `comment.sh` rejects empty/unset `PR_COMMENT_TOKEN` and handles missing
  plan file gracefully

### Changed

- Bump `bats-core/bats-action` from 3.0.0 to 4.0.0

## [1.0.0] - 2026-02-17

### Added

- `checksum` output from `octorules plan --checksum` for drift protection workflows
- BATS unit tests for `scripts/run.sh` and `scripts/comment.sh`
- CI workflow with lint and test jobs
- Release workflow for draft releases on tag push
- Major version tag update workflow on release publish
- Dependabot configuration for GitHub Actions dependencies
- This changelog

### Changed

- Removed `--format markdown` flag — plan output format is now configured via `manager.plan_outputs` in the octorules config file
- Makefile default target now runs both `lint` and `test`

### Removed

- Standalone `lint.yml` workflow (merged into `ci.yml`)
