#!/bin/bash

# Start CDK mint with FakeWallet backend
# Usage: ./CI/start-cdk.sh [port]

set -e

PORT=${1:-3339}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDK_DIR="${SCRIPT_DIR}/.cdk"
LOG_FILE="${SCRIPT_DIR}/.cdk.log"
PID_FILE="${SCRIPT_DIR}/.cdk.pid"

echo "🚀 Starting CDK mint on port ${PORT}..."

cd "$CDK_DIR"

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

# Start mint in background with config
nohup cargo run --bin cdk-mintd --release -- --config "${SCRIPT_DIR}/.cdk-config/cdk-mintd.toml" > "$LOG_FILE" 2>&1 &
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
