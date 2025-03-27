#!/bin/bash

# version.sh - Generates consistent version strings for the Wanderer Notifier application
# This script implements a Semantic Versioning (SemVer) strategy

set -e

# Default values
VERSION_FILE="VERSION"
DEFAULT_VERSION="1.0.0"
GIT_SHORT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date +'%Y%m%d')

# Function to validate semver format
validate_semver() {
  local version=$1
  if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
    echo "Error: Version must follow SemVer format (X.Y.Z[-prerelease][+build])" >&2
    return 1
  fi
  return 0
}

# Function to get current version
get_current_version() {
  if [ -f "$VERSION_FILE" ]; then
    cat "$VERSION_FILE"
  else
    echo "$DEFAULT_VERSION"
  fi
}

# Function to create a new version
generate_version() {
  local version_type=$1
  local current=$(get_current_version)
  
  # Extract components
  local major=$(echo $current | cut -d. -f1)
  local minor=$(echo $current | cut -d. -f2)
  local patch=$(echo $current | cut -d. -f3 | cut -d- -f1 | cut -d+ -f1)
  
  case "$version_type" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      echo "No version change specified, using current version"
      ;;
  esac
  
  echo "$major.$minor.$patch"
}

# Function to generate a full version string with metadata
generate_full_version() {
  local version=$1
  local env=${2:-prod}
  
  if [ "$env" = "dev" ]; then
    echo "${version}-dev+${BUILD_DATE}.${GIT_SHORT_SHA}"
  else
    echo "${version}+${BUILD_DATE}.${GIT_SHORT_SHA}"
  fi
}

# Function to generate Docker tags
generate_docker_tags() {
  local version=$1
  
  # Extract components
  local major=$(echo $version | cut -d. -f1)
  local minor=$(echo $version | cut -d. -f2)
  
  echo "v${version}"
  echo "v${major}.${minor}"
  echo "v${major}"
  echo "latest"
}

# Function to update version in project files
update_version_files() {
  local version=$1
  local full_version=$2
  
  # Update VERSION file
  echo "$version" > "$VERSION_FILE"
  
  # Update mix.exs if it exists
  if [ -f "mix.exs" ]; then
    sed -i "s/version: \"[^\"]*\"/version: \"$version\"/" mix.exs
    echo "Updated mix.exs with version $version"
  fi
  
  echo "Version files updated to $version (full: $full_version)"
}

# Main script execution
main() {
  local command=${1:-"get"}
  local version_type=${2:-""}
  local env=${3:-"prod"}
  
  case "$command" in
    get)
      get_current_version
      ;;
    bump)
      if [ -z "$version_type" ]; then
        echo "Error: Please specify a version type (major, minor, patch)" >&2
        exit 1
      fi
      local new_version=$(generate_version "$version_type")
      echo "$new_version"
      ;;
    full)
      local version=$(get_current_version)
      generate_full_version "$version" "$env"
      ;;
    tags)
      local version=$(get_current_version)
      generate_docker_tags "$version"
      ;;
    update)
      if [ -n "$version_type" ]; then
        local new_version=$(generate_version "$version_type")
        local full_version=$(generate_full_version "$new_version" "$env")
        update_version_files "$new_version" "$full_version"
      else
        local current_version=$(get_current_version)
        local full_version=$(generate_full_version "$current_version" "$env")
        echo "No version change requested. Current version: $current_version (full: $full_version)"
      fi
      ;;
    *)
      echo "Unknown command: $command" >&2
      echo "Usage: $0 [get|bump|full|tags|update] [major|minor|patch] [prod|dev]" >&2
      exit 1
      ;;
  esac
}

# Execute main function with all arguments
main "$@" 