# Docker Security Update - BuildKit Secrets Implementation

## Overview

This update addresses the security vulnerability where `NOTIFIER_API_TOKEN` was being passed as Docker build arguments, making it visible in image layers and history. The token is now handled securely using BuildKit secrets.

## Changes Made

### 1. Dockerfile Updates (`/workspace/Dockerfile`)

**Before:**
```dockerfile
ARG NOTIFIER_API_TOKEN
ENV NOTIFIER_API_TOKEN=$NOTIFIER_API_TOKEN
```

**After:**
```dockerfile
# Use secret mount to access token without storing in layers
RUN --mount=type=cache,target=/app/_build,sharing=locked \
    --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    --mount=type=secret,id=notifier_token,target=/run/secrets/notifier_token \
    export NOTIFIER_API_TOKEN=$(cat /run/secrets/notifier_token) && \
    mix compile --warnings-as-errors \
 && mix release --overwrite \
 && cp -r /app/_build/prod/rel/wanderer_notifier /app/release
```

### 2. CI/CD Workflow Updates

#### Main CI/CD Pipeline (`/.github/workflows/ci-cd.yml`)
- Added secrets file creation step
- Updated `docker/build-push-action` to use `secrets:` instead of `build-args:`
- Added cleanup step to remove secrets file

#### Dev Image Pipeline (`/.github/workflows/build-dev-image.yml`)
- Same security improvements as main pipeline
- Maintains dev image functionality with secure token handling

### 3. Docker Compose Updates (`/workspace/docker-compose.yml`)

**Before:**
```yaml
services:
  wanderer_notifier:
    image: guarzo/wanderer-notifier:latest
    env_file:
      - .env
```

**After:**
```yaml
services:
  wanderer_notifier:
    image: guarzo/wanderer-notifier:latest
    env_file:
      - .env
    environment:
      # NOTIFIER_API_TOKEN should be provided via .env file or environment
      # Token is no longer baked into the image for security
      - NOTIFIER_API_TOKEN=${NOTIFIER_API_TOKEN}
```

### 4. Testing Infrastructure

#### Local Testing Script (`/workspace/scripts/test_docker_secrets.sh`)
- Tests both insecure and secure implementations
- Validates that tokens don't leak into image layers
- Provides security verification

#### Secure Dockerfile (`/workspace/Dockerfile.secure`)
- Reference implementation for testing
- Demonstrates proper secrets handling

#### Docker Compose Test Setup (`/workspace/docker-compose.test.yml`)
- Local testing with Docker secrets
- Validates runtime token injection

#### Makefile Targets (`/workspace/Makefile`)
```bash
make docker.test.secrets      # Test current vs secure implementation
make docker.build.secure      # Build with secure secrets
make docker.test.secure       # Test secure build
```

## Security Benefits

### Before (Insecure)
- ❌ Token visible in `docker history` output
- ❌ Token stored in image layer metadata
- ❌ Token visible in build logs
- ❌ Token accessible via image inspection
- ❌ Token permanently baked into image

### After (Secure)
- ✅ Token not visible in image history
- ✅ Token not stored in any image layers
- ✅ Token only available during build
- ✅ Token injected at runtime
- ✅ No token persistence in final image

## Local Testing

### Quick Security Test
```bash
# Test current implementation for security issues
make docker.test.secrets

# Build and test secure version
make docker.test.secure
```

### Manual Testing
```bash
# Create test token
mkdir -p secrets
echo "your_test_token" > secrets/notifier_token.txt

# Build with secure secrets
docker build --secret id=notifier_token,src=secrets/notifier_token.txt -t secure-test .

# Verify token is not in history
docker history --no-trunc secure-test | grep -q "your_test_token" && echo "❌ LEAKED" || echo "✅ SECURE"

# Test runtime injection
docker run --rm -e NOTIFIER_API_TOKEN="runtime_token" secure-test /bin/sh -c 'echo $NOTIFIER_API_TOKEN'
```

### Docker Compose Testing
```bash
# Set up secrets
mkdir -p secrets
echo "your_token" > secrets/notifier_token.txt

# Test with compose
docker-compose -f docker-compose.test.yml up --build
```

## Migration Guide

### For Developers

1. **Local Development**: Token now provided via environment variables at runtime
2. **Testing**: Use new make targets for security validation
3. **CI/CD**: No changes needed - workflows updated automatically

### For Deployment

1. **Environment Variables**: Ensure `NOTIFIER_API_TOKEN` is available at runtime
2. **Docker Compose**: Update to use environment variable injection
3. **Kubernetes**: Use secrets instead of ConfigMaps for token

### Breaking Changes

- **Docker Images**: Old images still work, but new images require runtime token injection
- **Build Arguments**: `NOTIFIER_API_TOKEN` build arg no longer supported

## Verification

### Check Image Security
```bash
# Build image
docker build --secret id=notifier_token,src=/path/to/token -t test-image .

# Verify no token in layers
docker history --no-trunc test-image | grep -i "token" || echo "✅ No tokens found"

# Verify no token in environment
docker inspect test-image | jq '.[] | .Config.Env' | grep -i "notifier_api_token" || echo "✅ No tokens in env"
```

### Runtime Verification
```bash
# Test runtime injection
docker run --rm -e NOTIFIER_API_TOKEN="test123" test-image /bin/sh -c 'echo "Token: $NOTIFIER_API_TOKEN"'
```

## Files Modified

- ✅ `/workspace/Dockerfile` - Secure secrets implementation
- ✅ `/workspace/.github/workflows/ci-cd.yml` - CI/CD security updates
- ✅ `/workspace/.github/workflows/build-dev-image.yml` - Dev workflow security
- ✅ `/workspace/docker-compose.yml` - Runtime token injection
- ✅ `/workspace/Makefile` - Testing targets
- ✅ `/workspace/scripts/test_docker_secrets.sh` - Security validation
- ✅ `/workspace/Dockerfile.secure` - Reference implementation
- ✅ `/workspace/docker-compose.test.yml` - Test setup

## Compliance

This update ensures compliance with:
- Docker security best practices
- Container image security guidelines
- Secret management standards
- CI/CD security requirements

The token is now properly isolated and never persisted in image layers, eliminating the security vulnerability identified in the audit.