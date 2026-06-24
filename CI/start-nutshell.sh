#!/bin/bash

# Start Nutshell mint with FakeWallet backend
# Usage: ./CI/start-nutshell.sh [port]

set -e

PORT=${1:-3338}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUTSHELL_DIR="${SCRIPT_DIR}/.nutshell"
LOG_FILE="${SCRIPT_DIR}/.nutshell.log"
PID_FILE="${SCRIPT_DIR}/.nutshell.pid"

echo "🚀 Starting Nutshell mint on port ${PORT}..."

cd "$NUTSHELL_DIR"

# Kill any existing mint on this port
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "⚠️  Stopping existing mint (PID: $OLD_PID)..."
        kill "$OLD_PID" 2>/dev/null || true
        sleep 2
    fi
    rm -f "$PID_FILE"
fi

# Start mint in background
nohup poetry run mint --config "${SCRIPT_DIR}/.nutshell-config/nutshell.conf" > "$LOG_FILE" 2>&1 &
MINT_PID=$!

echo "$MINT_PID" > "$PID_FILE"
echo "✅ Mint started (PID: $MINT_PID)"
echo "📝 Log: $LOG_FILE"

# Wait for mint to be ready
echo "⏳ Waiting for mint to be ready..."
for i in {1..30}; do
    if curl -sf "http://localhost:${PORT}/v1/info" > /dev/null 2>&1; then
        echo "✅ Mint is ready!"
        curl -s "http://localhost:${PORT}/v1/info" | head -c 200
        echo ""
        exit 0
    fi
    sleep 1
done

echo "❌ Mint failed to start within 30 seconds"
cat "$LOG_FILE"
exit 1
