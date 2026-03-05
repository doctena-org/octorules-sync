# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
