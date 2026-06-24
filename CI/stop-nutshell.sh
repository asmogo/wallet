#!/bin/bash
set -euo pipefail

# stop-nutshell.sh — Stop Nutshell mint daemon
# Usage: ./CI/stop-nutshell.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/.nutshell.pid"
LOG_FILE="${SCRIPT_DIR}/.nutshell.log"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "🛑 Stopping Nutshell (PID: $PID)..."
        kill "$PID" 2>/dev/null || true
        sleep 1
    fi
    rm -f "$PID_FILE"
    echo "✅ Nutshell stopped"
else
    echo "⚠️  No Nutshell running"
fi

if [ -f "$LOG_FILE" ]; then
    echo ""
    echo "📝 Last 20 lines of Nutshell log:"
    tail -20 "$LOG_FILE"
fi
