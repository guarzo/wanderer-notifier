# WandererNotifier Development Guide

## Commands
- **Build**: `make compile` or `make compile.strict` (with warnings-as-errors)
- **Run**: `make run`, `make dev` (with assets), `make watch` (with auto-reload)
- **Test**: `make test` (all tests), `make test.<path>` (single file, e.g. `make test.services/character_kills_service`)
- **Format**: `make format` (runs mix format)
- **Lint**: `mix credo --strict` (ensure high code quality)
- **Clean**: `make clean`
- **Interactive Shell**: `make shell` or `iex -S mix`

## Code Style Guidelines
- **Architecture**: Follow functional, event-driven design with proper OTP supervision
- **Names**: PascalCase modules, snake_case functions/variables
- **Structure**: Single-responsibility functions, modules with clear boundaries
- **Functions**: Pure and immutable when possible, recursion over imperative loops
- **Error Handling**: Proper error isolation, "let it crash" philosophy, structured logs with trace tags
- **Documentation**: Use @moduledoc and @doc for all modules/functions, include @spec for public functions
- **Testing**: Mox for mocks, follow AAA pattern (Arrange, Act, Assert), ensure independent tests
- **Ash Resources**: Use Ash Framework properly for CRUD operations
- **Code Quality**: Maintain consistent style, focus on clarity, simplify logic where possible
- **Feature Flags**: Implement all new features with feature flags for controlled enablement