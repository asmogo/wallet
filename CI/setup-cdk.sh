#!/bin/bash
set -euo pipefail

# setup-cdk.sh — Get cdk-mintd binary ready
#   Linux:  download prebuilt binary + checksum verify
#   macOS:  build from source with cargo (Rust must be installed)
# Usage: ./CI/setup-cdk.sh [port]

PORT=${1:-3339}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDK_VERSION="0.17.1"
BIN_DIR="${SCRIPT_DIR}/.cdk-bin"
WORK_DIR="${SCRIPT_DIR}/.cdk-workdir"

echo "🔧 Setting up CDK mint (v${CDK_VERSION}) on port ${PORT}..."

mkdir -p "$BIN_DIR"

# Detect platform & arch
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "${ARCH}" in
    x86_64)  ASSET_ARCH="x86_64" ;;
    aarch64) ASSET_ARCH="aarch64" ;;
    arm64)   ASSET_ARCH="aarch64" ;;
    *)       echo "❌ Unsupported arch: ${ARCH}"; exit 1 ;;
esac

if [ "$OS" = "darwin" ]; then
    echo "⚠️  Prebuilt binary v${CDK_VERSION} is Linux-only."
    echo "   macOS detected (${ARCH}). Building from source with cargo..."

    cargo install --git https://github.com/cashubtc/cdk --tag "v${CDK_VERSION}" --root "${BIN_DIR}/.cargo" cdk-mintd 2>&1

    # Move binary to expected location and clean up
    mv "${BIN_DIR}/.cargo/bin/cdk-mintd" "${BIN_DIR}/cdk-mintd"
    rm -rf "${BIN_DIR}/.cargo"

    echo "✅ Built cdk-mintd v${CDK_VERSION} from source"
else
    # Linux: download prebuilt + checksum verify
    ASSET_NAME="cdk-mintd-${CDK_VERSION}-${ASSET_ARCH}"
    DOWNLOAD_URL="https://github.com/cashubtc/cdk/releases/download/v${CDK_VERSION}/${ASSET_NAME}"
    CHECKSUM_URL="https://github.com/cashubtc/cdk/releases/download/v${CDK_VERSION}/SHA256SUMS"

    echo "📥 Downloading ${ASSET_NAME}..."
    curl -fsSL -o "${BIN_DIR}/cdk-mintd" "$DOWNLOAD_URL"
    curl -fsSL -o "${BIN_DIR}/SHA256SUMS" "$CHECKSUM_URL"

    (cd "$BIN_DIR" && sha256sum -c SHA256SUMS --ignore-missing)
    rm -f "${BIN_DIR}/SHA256SUMS"
    chmod +x "${BIN_DIR}/cdk-mintd"

    echo "✅ cdk-mintd binary ready at ${BIN_DIR}/cdk-mintd"
fi

# Create work directory with config
mkdir -p "$WORK_DIR"

cat > "${WORK_DIR}/config.toml" << EOF
# CDK mint config for integration tests (FakeWallet backend)
[mint_info]
name = "CDK Test Mint"
description = "Integration-test mint with FakeWallet backend"
pubkey = ""
version = "cdk-integration-test"
contact = []

[listen]
host = "0.0.0.0"
port = ${PORT}

[database]
engine = "sqlite"
directory = ".cdk-workdir"

[ln]
ln_backend = "fakewallet"

[fakewallet]
seed = "00000000000000000000000000000000"
EOF

echo "✅ Config written to ${WORK_DIR}/config.toml"
echo "🚀 Start with: ./CI/start-cdk.sh"