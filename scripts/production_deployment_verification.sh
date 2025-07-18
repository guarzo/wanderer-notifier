#!/bin/bash

# Production Deployment Verification Script
# This script verifies that a Wanderer Notifier deployment is working correctly
# and all critical services are operational.

set -euo pipefail

# Configuration
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-http://localhost:4000/health}"
TIMEOUT="${TIMEOUT:-30}"
RETRY_COUNT="${RETRY_COUNT:-5}"
RETRY_DELAY="${RETRY_DELAY:-10}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Helper functions
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' is not available"
        return 1
    fi
}

make_request() {
    local url="$1"
    local expected_code="${2:-200}"
    local timeout="${3:-$TIMEOUT}"
    
    local response
    local http_code
    local body
    
    # Use write-out format to separate response body and HTTP code
    response=$(curl -s -w "\n__HTTP_CODE__%{http_code}" --max-time "$timeout" "$url" 2>/dev/null || echo "__HTTP_CODE__000")
    
    # Extract body and HTTP code using the delimiter
    body="${response%__HTTP_CODE__*}"
    http_code="${response##*__HTTP_CODE__}"
    
    if [[ "$http_code" == "$expected_code" ]]; then
        echo "$body"
        return 0
    else
        log_error "HTTP request to $url failed. Expected: $expected_code, Got: $http_code"
        return 1
    fi
}

wait_for_service() {
    local url="$1"
    local service_name="$2"
    local max_attempts="$3"
    local delay="$4"
    
    log_info "Waiting for $service_name to be ready..."
    
    for ((i=1; i<=max_attempts; i++)); do
        if make_request "$url" 200 10 >/dev/null 2>&1; then
            log_success "$service_name is ready"
            return 0
        fi
        
        if [[ $i -lt $max_attempts ]]; then
            log_info "Attempt $i/$max_attempts failed, retrying in ${delay}s..."
            sleep "$delay"
        fi
    done
    
    log_error "$service_name failed to start after $max_attempts attempts"
    return 1
}

# Verification functions
verify_prerequisites() {
    log_section "Verifying Prerequisites"
    
    local required_commands=("curl" "jq")
    
    for cmd in "${required_commands[@]}"; do
        if check_command "$cmd"; then
            log_success "$cmd is available"
        else
            log_error "Missing required command: $cmd"
            return 1
        fi
    done
}

format_uptime() {
    local seconds=$1
    
    if [[ "$seconds" == "unknown" ]] || ! [[ "$seconds" =~ ^[0-9]+$ ]]; then
        echo "$seconds"
        return
    fi
    
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    local formatted=""
    
    if [[ $days -gt 0 ]]; then
        formatted="${days}d "
    fi
    
    if [[ $hours -gt 0 ]]; then
        formatted="${formatted}${hours}h "
    fi
    
    if [[ $minutes -gt 0 ]]; then
        formatted="${formatted}${minutes}m "
    fi
    
    formatted="${formatted}${secs}s"
    echo "$formatted"
}

verify_basic_health() {
    log_section "Basic Health Check"
    
    if ! wait_for_service "$HEALTH_ENDPOINT" "Wanderer Notifier" "$RETRY_COUNT" "$RETRY_DELAY"; then
        return 1
    fi
    
    local response
    if response=$(make_request "$HEALTH_ENDPOINT"); then
        local status
        status=$(echo "$response" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
        
        if [[ "$status" == "OK" ]]; then
            log_success "Basic health check passed"
            
            # Extract additional info if available
            local version
            local uptime
            version=$(echo "$response" | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
            uptime=$(echo "$response" | jq -r '.uptime // "unknown"' 2>/dev/null || echo "unknown")
            
            log_info "Version: $version"
            log_info "Uptime: $(format_uptime "$uptime")"
        else
            log_error "Health check returned unexpected status: $status"
            return 1
        fi
    else
        log_error "Failed to get basic health status"
        return 1
    fi
}

verify_readiness() {
    log_section "Readiness Check"
    
    local readiness_url="${HEALTH_ENDPOINT}/ready"
    local response
    
    if response=$(make_request "$readiness_url"); then
        local status
        status=$(echo "$response" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
        
        if [[ "$status" == "ready" ]]; then
            log_success "Readiness check passed"
            
            # Show check details if available
            local checks
            if checks=$(echo "$response" | jq -r '.checks // {}' 2>/dev/null); then
                log_info "Readiness checks: $checks"
            fi
        else
            log_error "Readiness check failed with status: $status"
            log_info "Response: $response"
            return 1
        fi
    else
        log_error "Failed to get readiness status"
        return 1
    fi
}

verify_liveness() {
    log_section "Liveness Check"
    
    local liveness_url="${HEALTH_ENDPOINT}/live"
    local response
    
    if response=$(make_request "$liveness_url"); then
        local status
        status=$(echo "$response" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
        
        if [[ "$status" == "alive" ]]; then
            log_success "Liveness check passed"
            
            # Show process and memory info
            local process_count
            local memory_bytes
            process_count=$(echo "$response" | jq -r '.process_count // "unknown"' 2>/dev/null || echo "unknown")
            memory_bytes=$(echo "$response" | jq -r '.memory_bytes // "unknown"' 2>/dev/null || echo "unknown")
            
            log_info "Process count: $process_count"
            log_info "Memory usage: $memory_bytes bytes"
        else
            log_error "Liveness check failed with status: $status"
            log_info "Response: $response"
            return 1
        fi
    else
        log_error "Failed to get liveness status"
        return 1
    fi
}

verify_detailed_health() {
    log_section "Detailed Health Check"
    
    local details_url="${HEALTH_ENDPOINT}/details"
    local response
    
    if response=$(make_request "$details_url"); then
        log_success "Detailed health check accessible"
        
        # Extract key information
        local cache_enabled
        local feature_count
        cache_enabled=$(echo "$response" | jq -r '.cache_status.enabled // false' 2>/dev/null || echo "false")
        feature_count=$(echo "$response" | jq -r '.feature_flags | length // 0' 2>/dev/null || echo "0")
        
        log_info "Cache enabled: $cache_enabled"
        log_info "Feature flags count: $feature_count"
        
        # Check for any critical issues in the detailed response
        local error_count
        error_count=$(echo "$response" | jq -r '[.. | select(type == "string" and (contains("error") or contains("Error") or contains("failed")))] | length' 2>/dev/null || echo "0")
        
        if [[ "$error_count" -gt 0 ]]; then
            log_warning "Found $error_count potential error indicators in detailed health check"
        else
            log_success "No error indicators found in detailed health check"
        fi
    else
        log_warning "Detailed health check not accessible (this may be expected in production)"
    fi
}

verify_environment_configuration() {
    log_section "Environment Configuration"
    
    # Check for critical environment variables
    local critical_vars=("MIX_ENV" "PORT")
    local optional_vars=("DISCORD_BOT_TOKEN" "MAP_URL" "LICENSE_KEY")
    
    for var in "${critical_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            log_success "$var is set"
        else
            log_error "$var is not set"
            return 1
        fi
    done
    
    for var in "${optional_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            log_success "$var is configured"
        else
            log_warning "$var is not set (may be configured at runtime)"
        fi
    done
    
    # Verify MIX_ENV is set to prod
    if [[ "${MIX_ENV:-}" == "prod" ]]; then
        log_success "Running in production environment"
    else
        log_warning "Not running in production environment (MIX_ENV=${MIX_ENV:-unset})"
    fi
}

verify_container_health() {
    log_section "Container Health (if applicable)"
    
    # Check if running in container
    if [[ -f "/.dockerenv" ]] || [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]]; then
        log_info "Running in containerized environment"
        
        # Check resource limits and usage
        if [[ -f "/proc/meminfo" ]]; then
            local mem_total
            local mem_available
            mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
            mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
            
            log_info "Total memory: ${mem_total}KB"
            log_info "Available memory: ${mem_available}KB"
            
            # Check if we have sufficient memory (at least 100MB available)
            if [[ "$mem_available" -lt 102400 ]]; then
                log_warning "Low memory available: ${mem_available}KB"
            else
                log_success "Sufficient memory available"
            fi
        fi
        
        # Check if /app/data directory exists and is writable
        if [[ -d "/app/data" ]] && [[ -w "/app/data" ]]; then
            log_success "Data directory is accessible and writable"
        else
            log_warning "Data directory may not be properly configured"
        fi
    else
        log_info "Not running in containerized environment"
    fi
}

run_smoke_tests() {
    log_section "Smoke Tests"
    
    # Test that the service responds to HEAD requests (common for load balancers)
    if curl -s --head --max-time 10 "$HEALTH_ENDPOINT" | grep -q "200 OK"; then
        log_success "HEAD request test passed"
    else
        log_error "HEAD request test failed"
        return 1
    fi
    
    # Test response time
    local start_time
    local end_time
    local response_time
    
    start_time=$(date +%s%N)
    make_request "$HEALTH_ENDPOINT" >/dev/null
    end_time=$(date +%s%N)
    
    response_time=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    if [[ "$response_time" -lt 1000 ]]; then  # Less than 1 second
        log_success "Response time test passed (${response_time}ms)"
    else
        log_warning "Slow response time: ${response_time}ms"
    fi
}

# Main execution
main() {
    local exit_code=0
    
    log_info "Starting Wanderer Notifier Production Deployment Verification"
    log_info "Health endpoint: $HEALTH_ENDPOINT"
    log_info "Timeout: ${TIMEOUT}s, Retries: $RETRY_COUNT"
    
    # Run all verification steps
    verify_prerequisites || exit_code=1
    verify_environment_configuration || exit_code=1
    verify_basic_health || exit_code=1
    verify_readiness || exit_code=1
    verify_liveness || exit_code=1
    verify_detailed_health || exit_code=1
    verify_container_health || exit_code=1
    run_smoke_tests || exit_code=1
    
    # Final summary
    log_section "Verification Summary"
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "✅ All verification checks passed!"
        log_success "Wanderer Notifier deployment is healthy and ready for production use."
    else
        log_error "❌ Some verification checks failed!"
        log_error "Please review the errors above before proceeding with production deployment."
    fi
    
    exit $exit_code
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Environment variables:"
        echo "  HEALTH_ENDPOINT  Health check endpoint URL (default: http://localhost:4000/health)"
        echo "  TIMEOUT          Request timeout in seconds (default: 30)"
        echo "  RETRY_COUNT      Number of retry attempts (default: 5)"
        echo "  RETRY_DELAY      Delay between retries in seconds (default: 10)"
        echo ""
        echo "Example:"
        echo "  HEALTH_ENDPOINT=https://wanderer.example.com/health $0"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac