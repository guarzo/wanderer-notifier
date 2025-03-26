# Common Mix tasks for an Elixir project
.PHONY: compile clean test test.watch test.cover test.license test.license_manager test.bot_registration test.features test.config test.application test.mock format shell run deps.get deps.update build.npm dev watch

# Build tasks
compile:
	@mix compile

compile.strict:
	@mix compile --warnings-as-errors

clean:
	@mix clean

# Testing and formatting tasks
test:
	@./test/run_tests.sh

test.all:
	@MIX_ENV=test mix test --trace

test.mock:
	@MIX_ENV=test mix test --no-start

test.watch:
	@mix test.watch

test.cover:
	@mix test --cover

test.license:
	@MIX_ENV=test mix test test/wanderer_notifier/license_test.exs

test.license_manager:
	@MIX_ENV=test mix test test/wanderer_notifier/license_manager/client_test.exs

test.bot_registration:
	@MIX_ENV=test mix test test/wanderer_notifier/bot_registration_test.exs

test.features:
	@MIX_ENV=test mix test test/wanderer_notifier/features_test.exs

test.config:
	@MIX_ENV=test mix test test/wanderer_notifier/config_test.exs

test.application:
	@MIX_ENV=test mix test test/wanderer_notifier/application_test.exs

format:
	@mix format

# Running the application
shell:
	@iex -S mix

run:
	@mix run

# Build tasks for NPM components
build.npm: build.frontend build.chart-service

build.frontend:
	@echo "Building frontend assets..."
	@cd renderer && npm run build

build.chart-service:
	@echo "Installing chart-service dependencies if needed..."
	@cd chart-service && npm install --silent
	@echo "Chart service dependencies installed"

# Development commands with automatic asset rebuilding
dev: build.npm
	@iex -S mix

# Watch both frontend and start the application
watch:
	@echo "Starting watchers for both Elixir and frontend with auto-sync..."
	@(cd renderer && npm run sync) & (iex -S mix)

watch.frontend:
	@cd renderer && npm run watch

# Dependency management
deps.get:
	@mix deps.get

deps.update:
	@mix deps.update --all

# Alias for watch with initial clean+compile and npm build
s: clean compile build.npm
	@echo "Starting watchers for both Elixir and frontend with auto-sync..."
	@(cd renderer && npm run sync) & (iex -S mix)