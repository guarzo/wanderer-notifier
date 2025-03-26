# Build and Release Process Improvements

## Overview

This document outlines specific steps to address issues with the build and release process for the Wanderer Notifier application. The recommended improvements aim to reduce duplication, simplify configuration, and create a more maintainable deployment process.

## 1. Docker Compose Consolidation

### Current Issues:

- Multiple Docker Compose files (`docker-compose.yml` and `docker-compose-notifier.yml`) with overlapping functionality
- Different startup commands and environment configurations between files
- Inconsistent container naming and volume management

### Improvement Steps:

1. **Create a single consolidated Docker Compose file**:

   ```bash
   # Backup existing files
   cp docker-compose.yml docker-compose.yml.bak
   cp docker-compose-notifier.yml docker-compose-notifier.yml.bak

   # Create new consolidated file
   touch docker-compose.yml
   ```

2. **Structure the new file with profiles**:

   - Add a `standard` profile for basic deployments
   - Add a `database` profile for deployments with persistent storage
   - Example structure:

   ```yaml
   services:
     wanderer_notifier:
       image: guarzo/wanderer-notifier:latest
       profiles: ["standard", "database"]
       # Common configuration here

       # Use different command based on profile
       command: ${DB_COMMAND:-/app/bin/wanderer_notifier start}

     postgres:
       image: postgres:16-alpine
       profiles: ["database"]
       # Database configuration here
   ```

3. **Update documentation and CI/CD pipelines**:
   - Update README.md with new deployment instructions
   - Update CI workflows to use the new Docker Compose file
   - Add examples for different deployment profiles

## 2. Environment Variable Management

### Current Issues:

- Environment variables defined in multiple places
- Redundant loading of variables in runtime.exs
- Inconsistent environment variable conventions

### Improvement Steps:

1. **Consolidate environment variable definitions**:

   ```bash
   # Create a new comprehensive environment template
   cp .env.example .env.template
   ```

2. **Update runtime.exs to simplify variable loading**:

   - Remove redundant System.put_env() calls
   - Simplify configuration with more direct loading

3. **Standardize environment variable naming**:

   - Use consistent prefixes (e.g., `WANDERER_` for application-specific variables)
   - Document the naming conventions in a centralized location

4. **Create a environment variable validation script**:
   ```bash
   touch scripts/validate_env.sh
   chmod +x scripts/validate_env.sh
   ```
   - Script should validate required variables and provide helpful error messages

## 3. Release Configuration Simplification

### Current Issues:

- Confusing RELEASE_CONFIG variable usage
- Discrepancy between paths in Dockerfile and mix.exs
- Multiple configuration loading mechanisms

### Improvement Steps:

1. **Standardize configuration paths**:

   - Update mix.exs to use a consistent path:

   ```elixir
   config_providers: [
     {Config.Reader, {:system, "CONFIG_PATH", "/app/etc/wanderer_notifier.exs"}}
   ]
   ```

2. **Update Dockerfile to match the new path**:

   ```docker
   # Create configuration directory
   RUN mkdir -p /app/etc

   # Set the standardized environment variable
   ENV CONFIG_PATH=/app/etc
   ```

3. **Simplify runtime configuration loading**:

   - Update runtime.exs to avoid redundant loading
   - Document the configuration precedence clearly

4. **Create a configuration verification step**:
   - Add a startup script to verify configuration
   - Ensure consistent configuration across environments

## 4. Build Process Streamlining

### Current Issues:

- Complex build process spread across multiple files
- Redundant steps in GitHub Actions workflow
- Inefficient Docker image builds

### Improvement Steps:

1. **Simplify Makefile targets**:

   - Consolidate test targets using pattern matching
   - Create clear separation between development and production targets
   - Add documentation for each target group

2. **Optimize Dockerfile**:

   - Use multi-stage builds more effectively
   - Reduce the number of layers
   - Implement proper caching strategies
   - Example:

   ```docker
   # Base stage for dependencies
   FROM elixir:1.18-otp-27-slim AS deps
   # Install and cache dependencies

   # Build stage
   FROM deps AS builder
   # Build the application

   # Runtime stage
   FROM elixir:1.18-otp-27-slim AS runtime
   # Copy only necessary files from builder
   ```

3. **Streamline GitHub Actions workflow**:

   - Remove redundant steps
   - Implement better caching
   - Create a more predictable versioning strategy

4. **Create a versioning script**:
   ```bash
   touch scripts/version.sh
   chmod +x scripts/version.sh
   ```
   - Script should generate consistent version strings
   - Implement a clear versioning strategy (SemVer)

## 5. Database Initialization and Migration

### Current Issues:

- Inconsistent database initialization approach
- Migration commands embedded in Docker Compose
- No clear separation between application startup and database initialization

### Improvement Steps:

1. **Create a dedicated database initialization container**:

   - Add to Docker Compose:

   ```yaml
   services:
     db_init:
       image: guarzo/wanderer-notifier:latest
       profiles: ["database"]
       command: sh -c '/app/bin/wanderer_notifier eval "WandererNotifier.Release.createdb()" && /app/bin/wanderer_notifier eval "WandererNotifier.Release.migrate()"'
       depends_on:
         postgres:
           condition: service_healthy
   ```

2. **Update the Release module**:

   - Improve error handling and reporting
   - Add better logging for migration steps
   - Implement rollback capability for failed migrations

3. **Create a database backup solution**:

   ```yaml
   services:
     db_backup:
       image: postgres:16-alpine
       profiles: ["database"]
       command: sh -c 'pg_dump -h postgres -U postgres wanderer_notifier > /backups/$(date +%Y%m%d_%H%M%S).sql'
       volumes:
         - db_backups:/backups
   ```

4. **Add database health checks**:
   - Implement comprehensive health checks
   - Add monitoring for database connections

## 6. Testing and Validation

### Current Issues:

- Multiple test targets in Makefile
- No integration tests for Docker builds
- Lack of validation for configuration

### Improvement Steps:

1. **Consolidate test targets in Makefile**:

   ```makefile
   test.%:
     @MIX_ENV=test mix test test/wanderer_notifier/$*_test.exs
   ```

2. **Add Docker image validation tests**:

   ```bash
   touch scripts/test_docker_image.sh
   chmod +x scripts/test_docker_image.sh
   ```

   - Script should perform basic validation of built images
   - Verify that critical components are working

3. **Implement configuration validation**:

   - Create a validation module for checking configuration
   - Add warnings for deprecated or inconsistent configuration

4. **Add environment parity tests**:
   - Test for consistency between development and production

## Implementation Plan

1. **Phase 1: Documentation and Analysis**

   - Document all current environment variables and configurations
   - Identify all areas needing changes
   - Create a rollback plan

2. **Phase 2: Docker and Deployment Improvements**

   - Consolidate Docker Compose files
   - Improve Dockerfile
   - Update deployment scripts

3. **Phase 3: Configuration Management**

   - Standardize environment variable approach
   - Simplify configuration loading
   - Implement validation

4. **Phase 4: Build Process Improvements**

   - Update CI/CD pipelines
   - Optimize build steps
   - Add comprehensive testing

5. **Phase 5: Validation and Documentation**
   - Test all improvements
   - Update documentation
   - Train development team on new processes
