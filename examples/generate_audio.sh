#!/bin/bash

# RunPod API Health Check and Text tts Script
# This script checks the health of two RunPod endpoints and performs text tts

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Script settings
readonly MAX_ATTEMPTS=10
readonly RETRY_DELAY=60
readonly TIMEOUT=30
readonly LOG_FILE="runpod_script.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# logging functions
log_info() { log "${BLUE}INFO${NC}" "$@"; }
log_warn() { log "${YELLOW}WARN${NC}" "$@"; }
log_error() { log "${RED}ERROR${NC}" "$@"; }
log_success() { log "${GREEN}SUCCESS${NC}" "$@"; }

# Function to check if required tools are available
check_dependencies() {
    local missing_deps=()

    for cmd in curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install missing dependencies and try again"
        exit 1
    fi
}

# Function to validate environment
validate_environment() {
    if [[ -z "$RUNPOD_API_KEY" ]]; then
        log_error "RUNPOD_API_KEY is not set"
        exit 1
    fi

    if [[ -z "$ENDPOINT_ID" ]]; then
        log_error "Endpoint IDs are not properly configured"
        exit 1
    fi
}

# Function to ping an endpoint with better error handling
ping_endpoint() {
    local endpoint="$1"
    local name="$2"

    log_info "Pinging $name endpoint: $endpoint/ping"

    local response
    local http_code

    response=$(curl -s -w "%{http_code}" --max-time "$TIMEOUT" \
        -X GET "https://$ENDPOINT_ID.api.runpod.ai/ping" \
        -H "Authorization: Bearer $RUNPOD_API_KEY"
        2>/dev/null || echo "000")

    http_code="${response: -3}"

    if [[ "$http_code" == "200" ]]; then
        log_success "$name endpoint is healthy (HTTP $http_code)"
        return 0
    else
        log_warn "$name endpoint returned HTTP $http_code or failed to connect"
        return 1
    fi
}

# Function to check health of both endpoints
check_endpoints_health() {
    local attempt=1
    local summary_status=1
    local vllm_status=1

    log_info "Starting health check for RunPod endpoints..."
    log_info "Maximum attempts: $MAX_ATTEMPTS, Retry delay: ${RETRY_DELAY}s"

    while [[ $attempt -le $MAX_ATTEMPTS ]]; do
        log_info "Health check attempt $attempt/$MAX_ATTEMPTS"

        # Check both endpoints in parallel
        ping_endpoint "https://$ENDPOINT_ID.api.runpod.ai" "PING" &
        local pid1=$!



        # Wait for both to finish and capture exit codes
        wait $pid1
        ping_status=$?

        # Check if both are healthy
        if [[ $ping_status -eq 0 ]]; then
            log_success "Endpoints are healthy! ✓"
            return 0
        fi

        # Log which endpoints failed
        if [[ $ping_status -ne 0 ]]; then
            log_warn "Summary endpoint health check failed"
        fi

        # Don't sleep on the last attempt
        if [[ $attempt -lt $MAX_ATTEMPTS ]]; then
            log_warn "Health check failed. Retrying in ${RETRY_DELAY} seconds..."
            sleep "$RETRY_DELAY"
        fi

        ((attempt++))
    done

    log_error "Health check failed after $MAX_ATTEMPTS attempts"
    return 1
}

# Function to perform tts
generate_audio() {
    local http_code
    local input_file=$1
    local line_num=1

    log_info "Starting text to speech"

    while IFS= read -r line; do
        echo "Processing line $line_num..."

        http_code=$(echo "$line" | \
            curl -f -X POST "https://$ENDPOINT_ID.api.runpod.ai/tts" \
            --max-time 600 --header "Content-Type: application/json"  \
            --header "Authorization: Bearer $RUNPOD_API_KEY" \
            -d @- \
            -o "${line_num}.wav" || echo "000"
        )

        line_num=$((line_num+1))
    done < "$input_file"

    if [[ "$http_code" == "200" ]]; then
        log_success "Text to speech completed successfully! ✓"
        echo
        return 0
    else
        log_error "Text to speech failed with HTTP code: $http_code"
        log_error "Response: $response"
        return 1
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

RunPod API Health Check and Text tts Script

OPTIONS:
    -h, --help              Show this help message
    -f, --file FILE         JSONL file
    --timeout SECONDS       Request timeout in seconds (default: 30)

EXAMPLES:
    $0                      # Full health check + tts
    $0 -f mytext.jsonl

EOF
}

# Main function
main() {
    local text_file=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -f|--file)
                text_file="$2"
                shift 2
                ;;
            --timeout)
                readonly TIMEOUT="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Initialize
    log_info "=== RunPod API Script Started ==="
    log_info "Log file: $LOG_FILE"

    # Check dependencies and validate environment
    check_dependencies
    validate_environment


    if ! check_endpoints_health; then
        log_error "Cannot proceed with tts - endpoints are not healthy"
        exit 1
    fi


    # Perform tts unless skip flag is set
    if ! generate_audio "$text_file"; then
        log_error "Text to speech failed"
        exit 1
    fi

    log_success "=== Script completed successfully! ==="
}

# Run main function with all arguments
main "$@"
