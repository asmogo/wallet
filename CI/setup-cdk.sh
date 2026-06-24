#!/bin/bash

# Setup script for CDK mint with FakeWallet backend
# Usage: ./CI/setup-cdk.sh [port]

set -e

PORT=${1:-3339}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDK_DIR="${SCRIPT_DIR}/.cdk"

echo "🔧 Setting up CDK mint on port ${PORT}..."

# Clone CDK if not already present
if [ ! -d "$CDK_DIR" ]; then
    echo "📥 Cloning CDK repository..."
    git clone https://github.com/cashubtc/cdk.git "$CDK_DIR"
    cd "$CDK_DIR"
    git checkout main
fi

cd "$CDK_DIR"

# Install Rust if needed
if ! command -v cargo &> /dev/null; then
    echo "📦 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Build CDK mint
echo "📦 Building CDK mint with fake wallet..."
cargo build --bin cdk-mintd --release

# Create config directory
mkdir -p "${SCRIPT_DIR}/.cdk-config"

# Write configuration (TOML format for CDK)
cat > "${SCRIPT_DIR}/.cdk-config/cdk-mintd.toml" << EOF
[server]
port = ${PORT}
host = "0.0.0.0"
name = "CDK Test Mint"

[database]
backend = "memory"

[lightning]
backend = "fake"

[fake_wallet]
secret = "ci-test-secret-key-cdk"
EOF

echo "✅ CDK setup complete!"
echo "📁 Config: ${SCRIPT_DIR}/.cdk-config/cdk-mintd.toml"
echo "🚀 Start with: ./CI/start-cdk.sh ${PORT}"
