# Common Mix tasks for an Elixir project
.PHONY: compile clean test test.% format shell run deps.get deps.update build.npm dev watch

# ============================
# BUILD TASKS
# ============================
compile:
	@mix compile

compile.strict:
	@mix compile --warnings-as-errors

clean:
	@mix clean

# ============================
# TESTING AND FORMATTING TASKS
# ============================
test:
	@./test/run_tests.sh

# Pattern matching for test targets
test.%:
	@MIX_ENV=test mix test test/wanderer_notifier/$*_test.exs

test.all:
	@MIX_ENV=test mix test --trace

test.watch:
	@mix test.watch

test.cover:
	@mix test --cover

format:
	@mix format

# ============================
# RUNNING THE APPLICATION
# ============================
shell:
	@iex -S mix

run:
	@mix run

# ============================
# FRONTEND DEVELOPMENT TASKS
# ============================
# Build tasks for NPM components
build.npm: build.frontend

build.frontend:
	@echo "Building frontend assets..."
	@cd renderer && npm run build


# Development commands with automatic asset rebuilding
dev: build.npm
	@iex -S mix

# Watch both frontend and start the application
watch:
	@echo "Starting watchers for both Elixir and frontend with auto-sync..."
	@(cd renderer && npm run sync) & (iex -S mix)

watch.frontend:
	@cd renderer && npm run watch

# ============================
# DEPENDENCY MANAGEMENT
# ============================
deps.get:
	@mix deps.get

deps.update:
	@mix deps.update --all

# ============================
# PRODUCTION TASKS
# ============================
release:
	@MIX_ENV=prod mix release

# Build Docker image
docker.build:
	@docker build -t guarzo/wanderer-notifier:latest .

# Test Docker image
docker.test:
	@./scripts/test_docker_image.sh

# Build and test Docker image
docker: docker.build docker.test

# Generate version
version.get:
	@./scripts/version.sh get

version.bump:
	@./scripts/version.sh bump $(type)

version.update:
	@./scripts/version.sh update $(type)

# ============================
# SHORTCUTS
# ============================
# Alias for watch with initial clean+compile and npm build
s: clean compile build.npm
	@echo "Starting watchers for both Elixir and frontend with auto-sync..."
	@(cd renderer && npm run sync) & (iex -S mix)