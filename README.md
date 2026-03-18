# octorules-sync

This action runs `octorules` from [doctena-org/octorules](https://github.com/doctena-org/octorules) to deploy your WAF rules config.

octorules allows you to manage WAF and security rules (redirects, rewrites, headers, cache, WAF, rate limiting, and more) as YAML files and publish changes via your provider's API. Supported providers: [Cloudflare](https://github.com/doctena-org/octorules-cloudflare), [AWS WAF](https://github.com/doctena-org/octorules-aws), [Google Cloud Armor](https://github.com/doctena-org/octorules-google).

When you manage your octorules configuration in a GitHub repository, this [GitHub Action](https://help.github.com/actions/getting-started-with-github-actions/about-github-actions) allows you to test and publish your changes automatically using a [workflow](https://help.github.com/actions/configuring-and-managing-workflows) you define.

## Example workflows

### Cloudflare

```yaml
name: octorules-sync

on:
  push:
    branches:
      - main
    paths:
      - 'rules/**'
      - 'config.yaml'

jobs:
  publish:
    name: Publish rules from main
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install octorules-cloudflare
      - uses: doctena-org/octorules-sync@v1
        with:
          config_path: config.yaml
          doit: '--doit'
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

### AWS WAF

```yaml
      - run: pip install octorules-aws
      - uses: doctena-org/octorules-sync@v1
        with:
          config_path: config.yaml
          doit: '--doit'
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          AWS_DEFAULT_REGION: eu-central-1
```

### Google Cloud Armor

```yaml
      - run: pip install octorules-google
      - uses: doctena-org/octorules-sync@v1
        with:
          config_path: config.yaml
          doit: '--doit'
        env:
          GOOGLE_APPLICATION_CREDENTIALS: ${{ secrets.GOOGLE_APPLICATION_CREDENTIALS }}
```

### Multi-provider

Install all provider packages your config uses:

```yaml
      - run: pip install octorules-cloudflare octorules-aws octorules-google
```

## Inputs

### Secrets

Provider credentials are passed as environment variables using
[encrypted secrets](https://help.github.com/actions/configuring-and-managing-workflows/creating-and-storing-encrypted-secrets#about-encrypted-secrets).
The secret name and config syntax depend on your provider:

| Provider | Secret example | Config syntax |
|----------|---------------|---------------|
| [Cloudflare](https://github.com/doctena-org/octorules-cloudflare) | `CLOUDFLARE_API_TOKEN` | `token: env/CLOUDFLARE_API_TOKEN` |
| [AWS WAF](https://github.com/doctena-org/octorules-aws) | Standard boto3 credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) or IAM role | No `token` needed — boto3 credential chain |
| [Google Cloud Armor](https://github.com/doctena-org/octorules-google) | `GOOGLE_APPLICATION_CREDENTIALS` or Workload Identity | No `token` needed — Application Default Credentials |

The `env/` prefix in config values resolves environment variables at runtime. See each provider's README for full authentication details.

### `config_path`

Path, relative to your repository root, of the config file you would like octorules to use.

Default `"config.yaml"`.

### `doit`

Really do it? Set `"--doit"` to apply changes; Any other string to only plan.

Default `""` (empty string, plan only).

### `force`

Run octorules sync with `--force` to bypass safety thresholds? Set `"Yes"` to enable.

Default `"No"`.

### `checksum`

Pass a plan checksum to `octorules sync` for drift protection. When set, octorules verifies the current state matches the checksum before applying changes. Only used when `doit` is `"--doit"`.

Default `""` (empty string, no checksum verification).

### `phases`

Space separated list of rule phases to sync. Leave empty to sync all phases in the config file. Useful for targeting specific rule types.

Available phases depend on the configured provider. See each provider's README for the full list:
[Cloudflare](https://github.com/doctena-org/octorules-cloudflare) (23 phases) |
[AWS WAF](https://github.com/doctena-org/octorules-aws) (4 phases) |
[Google Cloud Armor](https://github.com/doctena-org/octorules-google) (4 phases)

Default `""` (empty string, all phases).

### `zones`

Space separated list of zones to sync, leave empty to sync all zones in the config file.

Default `""` (empty string, all zones).

### `lint`

Run `octorules lint` before plan/sync? Set `"Yes"` to enable. When enabled, the linter runs before the plan/sync step. Lint errors (exit code 1) block sync mode from applying changes; warnings do not.

Default `"No"`.

### `lint_severity`

Minimum lint severity to report: `"error"`, `"warning"`, or `"info"`.

Default `"warning"`.

### `lint_plan`

Plan tier override for Cloudflare lint entitlement checks: `"free"`, `"pro"`, `"business"`, `"enterprise"`. AWS WAF and Google Cloud Armor providers ignore this setting.

Default `""` (defaults to `"enterprise"`).

### `add_pr_comment`

Add plan as a comment, when triggered by a pull request? Set `"Yes"` to enable.

When enabled, this action creates a single PR comment with the plan output and **updates it in place** on subsequent runs (instead of creating a new comment each time).

Default `"No"`.

### `pr_comment_token`

Provide a token to use, if you set `add_pr_comment` to `"Yes"`.

**Important:** No token is automatically injected — you must explicitly pass a token (e.g. `${{ github.token }}`). The default `github.token` has sufficient permissions for same-repo PRs. For cross-repo or fork PRs, use a token with `pull_requests: write` scope.

Default `""` (empty string, must be provided when `add_pr_comment` is `"Yes"`).

## Outputs

### `plan`

The planned changes output from `octorules`. The output format is controlled via `manager.plan_outputs` in your octorules config file. Also written to `$GITHUB_WORKSPACE/octorules-sync.plan`.

### `log`

The `octorules` command log output. Also written to `$GITHUB_WORKSPACE/octorules-sync.log`.

### `exit_code`

The raw exit code from the `octorules` command. Useful for branching in downstream steps:

| Mode | Code | Meaning |
|------|------|---------|
| plan | `0`  | No changes detected |
| plan | `2`  | Changes detected |
| plan | `1`  | Error |
| sync | `0`  | Applied successfully |
| sync | `1`  | Error |

Example usage in a subsequent step:

```yaml
- name: Notify on changes
  if: steps.octorules.outputs.exit_code == '2'
  run: echo "Changes were detected"
```

### `checksum`

SHA-256 plan checksum for drift protection (plan mode only). Pass this value to a subsequent sync step via the `checksum` input to ensure the state hasn't drifted between plan and apply. Empty when running in sync mode or if no checksum was emitted.

### `lint_exit_code`

Exit code from `octorules lint`: `0` = clean, `1` = errors, `2` = warnings only, empty = lint disabled.

### `lint_results`

Lint results text. Empty when lint is disabled or clean.

## Linting

When `lint` is set to `"Yes"`, the action runs `octorules lint --exit-code` before the plan/sync step. Lint results are included in PR comments (when enabled) and exposed via the `lint_exit_code` and `lint_results` outputs.

- **Plan mode**: lint errors are reported but the plan still runs, so you can see both lint issues and planned changes. The action fails at the end if lint found errors.
- **Sync mode**: lint errors **block** the sync step entirely — changes are not applied. Warnings do not block sync.

### Wirefilter support (Cloudflare)

When linting Cloudflare rules, installing `octorules[wirefilter]` is **strongly recommended**. Without it, expression validation uses a regex-based fallback that can only extract field and function names. With wirefilter installed, expressions are parsed by Cloudflare's real [wirefilter](https://github.com/cloudflare/wirefilter) engine, enabling detection of syntax errors, unknown fields, type mismatches, and invalid operators that the regex fallback cannot catch.

AWS WAF and Google Cloud Armor providers include their own expression validation (CEL for Cloud Armor) and do not need wirefilter.

## Pull request plan comments

To have this action post the plan as a PR comment, configure your workflow to:

1. Run on the `pull_request` event
2. Set `add_pr_comment` to `"Yes"`
3. Provide a `pr_comment_token`

The action will create a single comment and update it in place on subsequent pushes to the same PR. Comment deduplication uses a hidden HTML marker (`<!-- octorules-sync-plan -->`) to find and update existing comments.

```yaml
name: octorules-plan

on:
  pull_request:

jobs:
  plan:
    name: Plan WAF rules changes
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install -r requirements.txt
      - uses: doctena-org/octorules-sync@v1
        with:
          config_path: config.yaml
          lint: 'Yes'
          add_pr_comment: 'Yes'
          pr_comment_token: '${{ github.token }}'
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

## Full workflow example

A common pattern is to plan on pull requests and apply on merge to main:

```yaml
name: octorules-sync

on:
  pull_request:
    paths:
      - 'rules/**'
      - 'config.yaml'
  push:
    branches:
      - main
    paths:
      - 'rules/**'
      - 'config.yaml'

jobs:
  plan:
    if: github.event_name == 'pull_request'
    name: Plan changes
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install -r requirements.txt
      - uses: doctena-org/octorules-sync@v1
        id: octorules
        with:
          config_path: config.yaml
          lint: 'Yes'
          add_pr_comment: 'Yes'
          pr_comment_token: '${{ github.token }}'
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}

  deploy:
    if: github.event_name == 'push'
    name: Deploy changes
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install -r requirements.txt
      - uses: doctena-org/octorules-sync@v1
        with:
          config_path: config.yaml
          doit: '--doit'
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

## Advanced: Phase filtering

To sync only specific rule phases, use the `phases` input:

```yaml
- uses: doctena-org/octorules-sync@v1
  with:
    config_path: config.yaml
    doit: '--doit'
    phases: 'cache_rules redirect_rules'
  env:
    CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

## Advanced: Checksum drift protection

The action outputs a `checksum` from `octorules plan --checksum`. Pass it to a
subsequent sync step to ensure the state hasn't drifted between plan and apply:

```yaml
jobs:
  plan:
    name: Plan
    runs-on: ubuntu-latest
    outputs:
      checksum: ${{ steps.plan.outputs.checksum }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install -r requirements.txt
      - uses: doctena-org/octorules-sync@v1
        id: plan
        with:
          config_path: config.yaml
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}

  deploy:
    needs: plan
    name: Deploy
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install -r requirements.txt
      - uses: doctena-org/octorules-sync@v1
        with:
          config_path: config.yaml
          doit: '--doit'
          checksum: '${{ needs.plan.outputs.checksum }}'
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

## Troubleshooting

### `octorules not found on PATH`

The action requires `octorules` and a provider package to be installed before it runs. Add an install step to your workflow:

```yaml
# Cloudflare
- run: pip install octorules-cloudflare

# AWS WAF
- run: pip install octorules-aws

# Google Cloud Armor
- run: pip install octorules-google

# Multiple providers
- run: pip install octorules-cloudflare octorules-aws

# Or use a requirements.txt
- run: pip install -r requirements.txt
```

### Provider token / invalid token errors

Ensure you have created a repository secret for your provider credentials and passed it as an environment variable. See the [Secrets](#secrets) section above for provider-specific examples. Config values that reference environment variables must use the `env/` prefix (e.g. `token: env/CLOUDFLARE_API_TOKEN`).

### Config file not found

The `config_path` input defaults to `config.yaml` in your repository root. If your config is elsewhere, set `config_path` accordingly. The path is relative to the repository root (workspace).

### PR comment permission errors

If the action fails to create or update PR comments, check that:

1. You passed a valid token via `pr_comment_token` (e.g. `${{ github.token }}`).
2. The token has `pull_requests: write` permission. For same-repo PRs, the default `github.token` is sufficient.
3. For fork PRs or cross-repo workflows, use a Personal Access Token or GitHub App token with appropriate scopes.

## Contributing

Contributions are welcome!

### Development setup

1. Fork and clone the repository.
2. Install the development dependencies:

   ```bash
   # macOS
   brew install shellcheck yamllint bats-core

   # Debian / Ubuntu
   apt-get install shellcheck yamllint bats
   ```

3. Run the full check suite:

   ```bash
   make
   ```

### Making changes

1. Create a branch from `main`.
2. Make your changes. If you modify `scripts/*.sh`, add or update the corresponding tests in `tests/`.
3. Run linting and tests before committing:

   ```bash
   make lint   # yamllint + shellcheck
   make test   # bats tests/
   ```

4. Open a pull request against `main`.

### Code style

- Shell scripts follow [ShellCheck](https://www.shellcheck.net/) recommendations.
- YAML files must pass `yamllint --no-warnings`.
- Use `set -euo pipefail` in new scripts.
- Prefer arrays for command construction (see `scripts/run.sh` for the pattern).

### Releases

Releases are automated. Push a semver tag (`v1.2.3`) to create a GitHub Release. Publishing the release updates the major version tag (`v1`) automatically.

Update `CHANGELOG.md` with your changes under the `[Unreleased]` section before tagging.
