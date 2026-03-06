# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
