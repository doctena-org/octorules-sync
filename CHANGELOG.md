# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Security

- Pin 3rd-party GitHub Actions to commit SHAs (Aikido finding)

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
