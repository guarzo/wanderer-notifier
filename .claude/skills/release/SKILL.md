# Release Workflow

Prescriptive steps for releasing a new version.

## Steps

1. **Run quality gates** — Ensure all checks pass:
   ```bash
   ./scripts/validate-quality.sh
   ```

2. **Bump version** — Update the version in `mix.exs`:
   - Find the `version:` field in `mix.exs`
   - Follow semantic versioning (MAJOR.MINOR.PATCH)
   - Commit the version bump

3. **Push to main** — The CI/CD pipeline handles the rest:
   - CI runs all quality gates (format, compile, dialyzer, credo, tests)
   - Auto-tag job extracts version from `mix.exs` and creates a git tag
   - Docker job builds multi-arch images (amd64, arm64) and pushes to DockerHub
   - Release job creates a GitHub Release with changelog

4. **Verify deployment** — After CI completes:
   - Check the GitHub Actions workflow succeeded
   - Verify the Docker image is available: `docker pull guarzo/wanderer-notifier:vX.Y.Z`
   - Check the GitHub Release was created with correct changelog

## Manual Docker Build (if needed)

```bash
make docker.build     # Build Docker image locally
make docker.test      # Test Docker image
```

## Rollback

If a release has issues:
1. Revert the commit on main
2. Push the revert — CI will create a new version tag and image
