#!/bin/bash
set -euo pipefail

# stop-cdk.sh — Stop CDK mint daemon (Docker container on macOS, process on Linux)
# Usage: ./CI/stop-cdk.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/.cdk.pid"
LOG_FILE="${SCRIPT_DIR}/.cdk.log"
CONTAINER_NAME="cdk-mint"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')

if [ "$OS" = "darwin" ]; then
    # macOS: stop Docker container
    if docker ps -q --filter "name=${CONTAINER_NAME}" | grep -q .; then
        echo "🛑 Stopping CDK Docker container (${CONTAINER_NAME})..."
        docker stop "${CONTAINER_NAME}" > /dev/null 2>&1 || true
        docker rm "${CONTAINER_NAME}" > /dev/null 2>&1 || true
        echo "✅ CDK stopped"
    else
        echo "⚠️  No CDK container running"
    fi
else
    # Linux: kill PID
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "🛑 Stopping CDK mint (PID: $PID)..."
            kill "$PID" 2>/dev/null || true
            sleep 1
        fi
        rm -f "$PID_FILE"
        echo "✅ CDK stopped"
    else
        echo "⚠️  No CDK mint running"
    fi
fi

if [ -f "$LOG_FILE" ]; then
    echo ""
    echo "📝 Last 20 lines of CDK log:"
    tail -20 "$LOG_FILE"
fi