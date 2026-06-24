#!/bin/bash

# Setup script for Nutshell mint with FakeWallet backend
# Usage: ./CI/setup-nutshell.sh [port]

set -e

PORT=${1:-3338}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUTSHELL_DIR="${SCRIPT_DIR}/.nutshell"

echo "🔧 Setting up Nutshell mint on port ${PORT}..."

# Clone Nutshell if not already present
if [ ! -d "$NUTSHELL_DIR" ]; then
    echo "📥 Cloning Nutshell repository..."
    git clone https://github.com/cashubtc/nutshell.git "$NUTSHELL_DIR"
    cd "$NUTSHELL_DIR"
    git checkout main
fi

cd "$NUTSHELL_DIR"

# Install Poetry if needed
if ! command -v poetry &> /dev/null; then
    echo "📦 Installing Poetry..."
    pip install poetry
fi

# Install dependencies
echo "📦 Installing Nutshell dependencies..."
poetry install

# Create config directory if it doesn't exist
mkdir -p "${SCRIPT_DIR}/.nutshell-config"

# Write configuration
cat > "${SCRIPT_DIR}/.nutshell-config/nutshell.conf" << EOF
mint_database = memory
mint_listen_port = ${PORT}
mint_host = 0.0.0.0
mint_listen_lightning = false

backend = FakeWallet

fake_wallet_secret = "ci-test-secret-key-${PORT}"
EOF

echo "✅ Nutshell setup complete!"
echo "📁 Config: ${SCRIPT_DIR}/.nutshell-config/nutshell.conf"
echo "🚀 Start with: ./CI/start-nutshell.sh ${PORT}"
