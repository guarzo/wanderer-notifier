# Build and Release Process Improvements

## Overview

This document outlines specific steps to address issues with the build and release process for the Wanderer Notifier application. The recommended improvements aim to reduce duplication, simplify configuration, and create a more maintainable deployment process.


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
