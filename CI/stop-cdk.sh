#!/bin/bash
set -euo pipefail

# stop-cdk.sh — Stop CDK mint daemon
# Usage: ./CI/stop-cdk.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/.cdk.pid"
LOG_FILE="${SCRIPT_DIR}/.cdk.log"

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

if [ -f "$LOG_FILE" ]; then
    echo ""
    echo "📝 Last 20 lines of CDK log:"
    tail -20 "$LOG_FILE"
fi
