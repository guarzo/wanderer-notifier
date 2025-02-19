# Common Mix tasks for an Elixir project
.PHONY: compile clean test format shell run deps.get deps.update

# Build tasks
compile:
	@mix compile

clean:
	@mix clean

# Testing and formatting tasks
test:
	@mix test

format:
	@mix format

# Running the application
shell:
	@iex -S mix

run:
	@mix run

# Dependency management
deps.get:
	@mix deps.get

deps.update:
	@mix deps.update --all

s: clean compile shell