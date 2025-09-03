#!/usr/bin/env bash
set -e

# Ensure PORT is set by the serverless platform
: "${PORT:?Environment variable PORT must be set}"

# Record startup time for the warm-up window
export START_TIME=$(date +%s)

# Build vLLM command with base arguments
CMD="uv run server.py"

# Add command line arguments as additional vLLM parameters
if [ "$#" -gt 0 ]; then
    echo "Adding command line arguments: $*"
    CMD="$CMD $*"
fi

# Log the final command for debugging
echo "Starting with command: $CMD"


# Start vLLM server in the background
eval "$CMD" &

# Start Caddy as the reverse proxy
exec caddy run --config Caddyfile --adapter caddyfile