# CI/CD Pipeline Documentation

## A. Goals

- Single Source of Truth for build, test, lint, and release steps.
- Reusable Workflows with workflow_call to avoid duplication.
- Parameterization for adhoc vs automatic vs release modes.
- Fail-Fast & Readability: clear jobs, inputs, and outputs.

## B. Reusable "build-and-test" Workflow

File: `.github/workflows/build-and-test.yml`

```yaml
name: Build & Test

on:
  workflow_call:
    inputs:
      mode:
        type: choice
        required: true
        options: [adhoc, automatic, release]
      branch:
        type: string
        required: false
      version_type:
        type: choice
        required: false
        options: [patch, minor, major]
    secrets:
      DOCKERHUB_PAT:
        required: false
      NOTIFIER_API_TOKEN:
        required: true
      FAKE_DISCORD_TOKEN:
        required: true

jobs:
  checkout:
    name: Checkout & Cache
    runs-on: ubuntu-latest
    outputs:
      cache-key: ${{ steps.cache-key.outputs.value }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - id: cache-key
        run: echo "value=${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}-1.18-27" >> $GITHUB_OUTPUT
      - name: Restore Cache
        uses: actions/cache@v3
        with:
          key: ${{ steps.cache-key.outputs.value }}
          path: |
            deps
            _build
            priv/static
```

## C. Main "Orchestrator" Workflow

File: `.github/workflows/ci.yml`

```yaml
name: CI Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:
    inputs:
      mode:
        description: "Run mode"
        required: false
        default: "automatic"
        type: choice
        options: [adhoc, automatic, release]
      branch:
        description: "Branch for adhoc"
        required: false
      version_type:
        description: "Bump type for release"
        required: false
        default: "patch"
        type: choice
        options: [patch, minor, major]

jobs:
  run:
    uses: ./.github/workflows/build-and-test.yml
    with:
      mode: ${{ github.event.inputs.mode || 'automatic' }}
      branch: ${{ github.event.inputs.branch }}
      version_type: ${{ github.event.inputs.version_type }}
    secrets: inherit
```

- Push/PR to main triggers the full CI.
- Manual dispatch (workflow_dispatch) allows adhoc or release flows.

## D. Release Steps in Same Orchestrator

You can extend build-and-test.yml with conditional jobs:

```yaml
release:
  name: Bump Version & Tag
  needs: docker-validate
  if: inputs.mode == 'release'
  steps:
    - name: Bump version in files
      run: ./scripts/version.sh bump ${{ inputs.version_type }}
    - name: Commit & Tag
      run: |
        git config user.email "actions@github.com"
        git config user.name "GitHub Actions"
        git add VERSION mix.exs
        git commit -m "Release v$(cat VERSION) [skip ci]"
        git tag -a "v$(cat VERSION)" -m "Release v$(cat VERSION)"
        git push origin main --tags
    - name: Create GitHub Release
      uses: softprops/action-gh-release@v1
      with:
        tag_name: "v$(cat VERSION)"
        name: "Release v$(cat VERSION)"
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## E. Remove Redundant Workflow Files

After this:

- Delete `.github/workflows/adhoc.yml`, `automatic.yml`, `release.yml`, `test.yml`.
- Eliminate custom composite actions that duplicate build-and-test.yml steps.

## F. Milestones & Checklist

| Task                                                   | Done |
| ------------------------------------------------------ | ---- |
| Create build-and-test.yml reusable workflow            | [ ]  |
| Create ci.yml to call the reusable workflow            | [ ]  |
| Add release job conditioned on mode == 'release'       | [ ]  |
| Remove old adhoc/automatic/release/test workflow files | [ ]  |
| Verify secrets and inputs are properly passed through  | [ ]  |
| Update README-GH-PAGES.md or docs to reflect new usage | [ ]  |
| Confirm pipeline runs successfully on push, PR, manual | [ ]  |

By consolidating into one reusable build-and-test workflow and a thin orchestrator, you'll drastically cut duplication, simplify maintenance, and make it easy to extend or debug your CI/CD pipeline.
