#!/bin/bash

# Stop Nutshell mint
# Usage: ./CI/stop-nutshell.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/.nutshell.pid"
LOG_FILE="${SCRIPT_DIR}/.nutshell.log"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "🛑 Stopping Nutshell mint (PID: $PID)..."
        kill "$PID" 2>/dev/null || true
        sleep 2
    fi
    rm -f "$PID_FILE"
    echo "✅ Mint stopped"
else
    echo "⚠️  No mint running"
fi

# Show last 20 lines of log
if [ -f "$LOG_FILE" ]; then
    echo ""
    echo "📝 Last 20 lines:"
    tail -20 "$LOG_FILE"
fi
