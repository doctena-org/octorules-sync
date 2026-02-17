# octorules-sync

This action runs `octorules` from [doctena-org/octorules](https://github.com/doctena-org/octorules) to deploy your Cloudflare Rules config.

octorules allows you to manage your Cloudflare Rules (redirects, rewrites, headers, cache, WAF, rate limiting, and more) in a portable YAML format and publish changes via the Cloudflare API. It is extensible and customizable.

When you manage your octorules configuration in a GitHub repository, this [GitHub Action](https://help.github.com/actions/getting-started-with-github-actions/about-github-actions) allows you to test and publish your changes automatically using a [workflow](https://help.github.com/actions/configuring-and-managing-workflows) you define.

## Example workflow

```yaml
name: octorules-sync

on:
  # Deploy config whenever rule changes are pushed to main.
  push:
    branches:
      - main
    paths:
      - 'rules/**'
      - 'config.yaml'

jobs:
  publish:
    name: Publish Cloudflare Rules from main
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install octorules
      - uses: doctena-org/octorules-sync@main
        with:
          config_path: config.yaml
          doit: '--doit'
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

## Inputs

### Secrets

To authenticate with Cloudflare, this action uses
[encrypted secrets](https://help.github.com/actions/configuring-and-managing-workflows/creating-and-storing-encrypted-secrets#about-encrypted-secrets)
you've configured on your repository. Create a secret called
`CLOUDFLARE_API_TOKEN` with your Cloudflare API token, and pass it as an
environment variable in your workflow:

```yaml
env:
  CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

Your `config.yaml` should reference it with:

```yaml
cloudflare:
  token: env/CLOUDFLARE_API_TOKEN
```

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

Available phases: `redirect_rules`, `url_rewrite_rules`, `request_header_rules`, `response_header_rules`, `config_rules`, `origin_rules`, `cache_rules`, `compression_rules`, `custom_error_rules`, `waf_custom_rules`, `rate_limiting_rules`.

Default `""` (empty string, all phases).

### `zones`

Space separated list of zones to sync, leave empty to sync all zones in the config file.

Default `""` (empty string, all zones).

### `add_pr_comment`

Add plan as a comment, when triggered by a pull request? Set `"Yes"` to enable.

When enabled, this action creates a single PR comment with the plan output and **updates it in place** on subsequent runs (instead of creating a new comment each time).

Default `"No"`.

### `pr_comment_token`

Provide a token to use, if you set `add_pr_comment` to `"Yes"`.

Default `"Not set"`.

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

## Pull request plan comments

To have this action post the plan as a PR comment, configure your workflow to:

1. Run on the `pull_request` event
2. Set `add_pr_comment` to `"Yes"`
3. Provide a `pr_comment_token`

The action will create a single comment and update it in place on subsequent pushes to the same PR.

```yaml
name: octorules-plan

on:
  pull_request:

jobs:
  plan:
    name: Plan Cloudflare Rules changes
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install octorules
      - uses: doctena-org/octorules-sync@main
        with:
          config_path: config.yaml
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
      - run: pip install octorules
      - uses: doctena-org/octorules-sync@main
        id: octorules
        with:
          config_path: config.yaml
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
      - run: pip install octorules
      - uses: doctena-org/octorules-sync@main
        with:
          config_path: config.yaml
          doit: '--doit'
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

## Advanced: Phase filtering

To sync only specific rule phases, use the `phases` input:

```yaml
- uses: doctena-org/octorules-sync@main
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
      - run: pip install octorules
      - uses: doctena-org/octorules-sync@main
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
      - run: pip install octorules
      - uses: doctena-org/octorules-sync@main
        with:
          config_path: config.yaml
          doit: '--doit'
          checksum: '${{ needs.plan.outputs.checksum }}'
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

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
- Use `set -o pipefail` in new scripts.
- Prefer arrays for command construction (see `scripts/run.sh` for the pattern).

### Releases

Releases are automated. Push a semver tag (`v1.2.3`) to create a draft GitHub Release. Publishing the release updates the major version tag (`v1`) automatically.

Update `CHANGELOG.md` with your changes under the `[Unreleased]` section before tagging.
