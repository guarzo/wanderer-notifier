# Common Mix tasks for an Elixir project
.PHONY: compile clean test test.% format shell run deps.get deps.update build.npm dev watch ui.dev server-status

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

# ============================
# SHORTCUTS
# ============================
# Alias for watch with initial clean+compile and npm build
s: clean compile build.npm
	iex -S mix

# ============================
# DIAGNOSTIC TOOLS
# ============================
# Check web server status and connectivity
server-status:
	@echo "Checking web server connectivity..."
	@echo "Attempting to connect to localhost:4000..."
	@curl -s http://localhost:4000/health > /dev/null && echo "✅ HTTP server is responsive" || echo "❌ Cannot connect to HTTP server"
	@echo "\nChecking port bindings:"
	@netstat -tulpn 2>/dev/null | grep 4000 || ss -tulpn 2>/dev/null | grep 4000 || echo "No process found listening on port 4000"
	@echo "\nDetailed health info:"
	@curl -s http://localhost:4000/health/details || echo "Cannot fetch detailed health info"