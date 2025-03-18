# Common Mix tasks for an Elixir project
.PHONY: compile clean test test.watch test.cover test.license test.license_manager test.bot_registration test.features test.config test.application test.mock format shell run deps.get deps.update build.npm dev watch

# Build tasks
compile:
	@mix compile

clean:
	@mix clean

# Testing and formatting tasks
test:
	@MIX_ENV=test mix test

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

# Development commands with automatic asset rebuilding
dev:
	@iex -S mix

watch:
	@cd renderer && npm run watch && cd ..

build.npm: 
	cd renderer && npm run build && cd ..

# Dependency management
deps.get:
	@mix deps.get

deps.update:
	@mix deps.update --all

# Original command with automatic asset rebuilding
s: clean compile
	@iex -S mix