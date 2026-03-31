# Quality Check

Run all mandatory quality gates before committing code.

## Steps

1. **Compile** — Verify no compilation errors:
   ```bash
   mix compile
   ```
   If errors occur, fix them before proceeding.

2. **Run tests** — All tests must pass (100%):
   ```bash
   mix test
   ```
   If failures occur, fix them before proceeding.

3. **Credo** — No static analysis issues allowed:
   ```bash
   mix credo --strict
   ```
   Common issues: max function nesting depth is 2, max ABC complexity is 30, function clauses must be grouped together.

4. **Dialyzer** — No type specification warnings:
   ```bash
   MIX_ENV=dev mix dialyzer
   ```
   Note: 3 pre-existing skipped errors are expected.

5. **Format check** (optional but recommended):
   ```bash
   mix format --check-formatted
   ```

## Quick Run

Use the validation script to run all gates at once:
```bash
./scripts/validate-quality.sh
```

## When to Run

- Before every commit
- Before creating a pull request
- After resolving merge conflicts
