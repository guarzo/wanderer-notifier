# Common Mix tasks for an Elixir project
.PHONY: compile clean test test.% format shell run deps.get deps.update dev watch ui.dev server-status

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

# Test Docker secrets implementation
docker.test.secrets:
	@./scripts/test_docker_secrets.sh

# Build secure Docker image (with secrets)
docker.build.secure:
	@echo "Building secure Docker image..."
	@mkdir -p secrets && echo "test_token_123" > secrets/notifier_token.txt
	@docker build -f Dockerfile.secure --secret id=notifier_token,src=secrets/notifier_token.txt -t guarzo/wanderer-notifier:secure .
	@rm -f secrets/notifier_token.txt

# Test secure Docker build
docker.test.secure: docker.build.secure
	@echo "Testing secure Docker implementation..."
	@docker history --no-trunc guarzo/wanderer-notifier:secure | grep -q "test_token" && echo "❌ Token found in history!" || echo "✅ Token not found in history"

# Build and test Docker image
docker: docker.build docker.test

# ============================
# SHORTCUTS
# ============================
# Alias for watch with initial clean+compile
s: clean compile
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