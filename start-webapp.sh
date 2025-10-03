#!/usr/bin/env bash
set -euo pipefail

# Start the Dataserver2 Collections Web Application

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
: "${HOST:=0.0.0.0}"
: "${PORT:=5000}"
: "${PYTHON:=python3}"

echo "Starting Dataserver2 Collections Web Application..."
echo "Host: $HOST"
echo "Port: $PORT"
echo ""

# Check if Python is available
if ! command -v "$PYTHON" >/dev/null 2>&1; then
    echo "Error: Python 3 is required but not found" >&2
    exit 1
fi

# Check if pip is available
if ! command -v pip3 >/dev/null 2>&1 && ! command -v pip >/dev/null 2>&1; then
    echo "Error: pip is required but not found" >&2
    exit 1
fi

# Install dependencies if not already installed
if ! "$PYTHON" -c "import flask" 2>/dev/null; then
    echo "Installing dependencies..."
    pip3 install -r requirements.txt || pip install -r requirements.txt
fi

# Set environment variables
export HOST="$HOST"
export PORT="$PORT"

# Generate a random secret key if not set
if [[ -z "${SECRET_KEY:-}" ]]; then
    export SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
fi

echo "Starting server at http://$HOST:$PORT"
echo "Press Ctrl+C to stop"
echo ""

# Start the application
exec "$PYTHON" app.py
