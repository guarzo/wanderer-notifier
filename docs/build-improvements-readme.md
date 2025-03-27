# Build Process Improvements

This document describes the implementation of the build and release process improvements for the Wanderer Notifier application.

## Implemented Improvements

### 1. Version Management

We've created a robust versioning script (`scripts/version.sh`) that provides:

- **Semantic Versioning**: Follows the SemVer standard (MAJOR.MINOR.PATCH)
- **Consistent Version Generation**: Creates standardized version strings
- **Docker Tag Management**: Generates appropriate Docker tags
- **Build Metadata**: Adds build date and git information

Usage:

```bash
# Get current version
./scripts/version.sh get

# Bump version (type can be major, minor, or patch)
./scripts/version.sh bump patch

# Update version files
./scripts/version.sh update minor

# Get full version with metadata
./scripts/version.sh full

# List Docker tags
./scripts/version.sh tags
```

### 2. Docker Image Optimization

We've improved the Dockerfile with:

- **Multi-stage Builds**: Separate stages for dependencies, building, and runtime
- **Layer Reduction**: More efficient layer structure
- **Improved Caching**: Better cache utilization
- **Health Check**: Added container health monitoring
- **Smaller Runtime Image**: Only necessary components included

### 3. Docker Image Validation

We've created a dedicated testing script (`scripts/test_docker_image.sh`) that:

- Validates the Docker image's key components
- Tests the application's core functionality
- Verifies script presence and permissions
- Checks system dependencies

Usage:

```bash
# Test the default image (latest tag)
./scripts/test_docker_image.sh

# Test a specific image tag
./scripts/test_docker_image.sh -t v1.0.0

# Test a custom image name
./scripts/test_docker_image.sh -i mycustom/image -t latest
```

### 4. Makefile Streamlining

We've simplified the Makefile with:

- **Pattern Matching**: Consolidated test targets using pattern matching
- **Clear Sections**: Organized targets into logical groups
- **Documentation**: Added clear section headers
- **New Targets**: Added Docker and version management targets

New targets include:

```
# Build Docker image
make docker.build

# Test Docker image
make docker.test

# Build and test Docker image
make docker

# Version management
make version.get
make version.bump type=patch
make version.update type=minor
```

### 5. GitHub Actions Workflow Improvements

We've streamlined the GitHub Actions workflows:

- **Efficient Caching**: Better dependency caching
- **Consistent Versioning**: Using the version.sh script
- **Simplified Builds**: Removed redundant steps
- **Image Testing**: Added proper image testing
- **Release Automation**: Improved GitHub release creation

### 6. Database Management

We've enhanced database handling with:

- **Dedicated Initialization**: Separate container for database setup
- **Backup Solution**: Added database backup service
- **Restore Capability**: Added database restore service
- **Clear Separation**: Better separation between application and database operations

## How to Use

### Building a Release

Manually:

```bash
# Update version
./scripts/version.sh update patch

# Build Docker image
make docker
```

Using GitHub Actions:

1. Navigate to the Actions tab
2. Choose the "Release" workflow
3. Click "Run workflow"
4. Select the version type (patch, minor, major)
5. Run the workflow

### Docker Compose

Two configurations are available:

1. **Standard**: `docker-compose.yml` - For standalone operation
2. **With Database**: `docker-compose-db.yml` - Includes PostgreSQL and DB management

To use with database:

```bash
docker-compose -f docker-compose-db.yml up -d
```

To run database initialization:

```bash
docker-compose -f docker-compose-db.yml --profile database up db_init
```

To backup the database:

```bash
docker-compose -f docker-compose-db.yml --profile backup up db_backup
```

To restore the database:

```bash
BACKUP_FILE=wanderer_20240327_123045.sql docker-compose -f docker-compose-db.yml --profile restore up db_restore
```

## Future Improvements

Potential areas for further enhancement:

1. Add database migration testing
2. Implement a staging environment
3. Add performance testing
4. Create a local development container
5. Improve documentation automation
