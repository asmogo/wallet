#!/bin/bash
set -euo pipefail

# start-cdk.sh — Launch CDK mint daemon
#                On macOS runs the Linux prebuilt binary inside Docker.
#                On Linux runs the binary directly.
# Usage: ./CI/start-cdk.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/.cdk-bin"
WORK_DIR="${SCRIPT_DIR}/.cdk-workdir"
LOG_FILE="${SCRIPT_DIR}/.cdk.log"
PID_FILE="${SCRIPT_DIR}/.cdk.pid"
CONTAINER_NAME="cdk-mint"

MINTD_BIN="${BIN_DIR}/cdk-mintd"

if [ ! -x "$MINTD_BIN" ]; then
    echo "❌ cdk-mintd not found. Run ./CI/setup-cdk.sh first"
    exit 1
fi

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# Read port from config
PORT=$(grep '^port' "${WORK_DIR}/config.toml" 2>/dev/null | head -1 | sed 's/.*= *//')
PORT=${PORT:-3339}

# --- Stop any existing instance ---
if [ "$OS" = "darwin" ]; then
    # Docker: stop existing container
    if docker ps -q --filter "name=${CONTAINER_NAME}" | grep -q .; then
        echo "🛑 Stopping existing CDK container..."
        docker stop "${CONTAINER_NAME}" > /dev/null 2>&1 || true
        docker rm "${CONTAINER_NAME}" > /dev/null 2>&1 || true
    fi
else
    # Linux: kill existing PID
    if [ -f "$PID_FILE" ]; then
        if pid=$(cat "$PID_FILE") && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            sleep 1
        fi
        rm -f "$PID_FILE"
    fi
fi

# --- Start the mint ---
echo "🚀 Starting CDK mint on port ${PORT}..."

if [ "$OS" = "darwin" ]; then
    # macOS: run the Linux binary inside a Docker container
    DOCKER_ARCH="arm64"
    [ "$ARCH" = "x86_64" ] && DOCKER_ARCH="amd64"

    # Ensure Docker daemon is running (macOS runners have Docker Desktop installed)
    if ! docker info > /dev/null 2>&1; then
        echo "🔧 Starting Docker daemon..."
        open -a Docker
        for i in {1..30}; do
            if docker info > /dev/null 2>&1; then
                echo "✅ Docker daemon is ready"
                break
            fi
            sleep 2
        done
        if ! docker info > /dev/null 2>&1; then
            echo "❌ Docker daemon failed to start within 60s"
            exit 1
        fi
    fi

    docker run -d \
        --name "${CONTAINER_NAME}" \
        --rm \
        --platform "linux/${DOCKER_ARCH}" \
        -p "${PORT}:${PORT}" \
        -v "${MINTD_BIN}:/usr/local/bin/cdk-mintd:ro" \
        -v "${WORK_DIR}:/workdir" \
        debian:bookworm-slim \
        cdk-mintd --work-dir /workdir > "$LOG_FILE" 2>&1

    DOCKER_PID=$(docker inspect "${CONTAINER_NAME}" --format '{{.State.Pid}}' 2>/dev/null || echo "")
    echo "$DOCKER_PID" > "$PID_FILE"
    echo "✅ CDK started in Docker container (${CONTAINER_NAME})"
    echo "📝 Log: $LOG_FILE"
else
    # Linux: run directly
    cd "$WORK_DIR"
    nohup "$MINTD_BIN" --work-dir "$WORK_DIR" > "$LOG_FILE" 2>&1 &
    MINT_PID=$!
    echo "$MINT_PID" > "$PID_FILE"
    echo "✅ CDK started (PID: $MINT_PID)"
    echo "📝 Log: $LOG_FILE"
fi

# --- Wait for ready ---
echo "⏳ Waiting for mint to be ready on port ${PORT}..."
for i in {1..30}; do
    if curl -sf "http://localhost:${PORT}/v1/info" > /dev/null 2>&1; then
        echo "✅ CDK mint is ready!"
        exit 0
    fi
    sleep 1
done

echo "❌ CDK mint failed to start within 30 seconds"
cat "$LOG_FILE"
exit 1