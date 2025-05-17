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

# Run the frontend in development mode
ui.dev:
	@echo "Starting Vite development server..."
	@cd renderer && npm run dev

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
	@echo "Starting application with frontend sync..."
	@echo "For better development experience, you can also run:"
	@echo "make shell      - Start only the backend server"
	@echo "make ui.dev     - Start Vite dev server (enables hot reload)"
	@(cd renderer && npm run sync) & (iex -S mix)

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