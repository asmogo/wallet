#!/bin/bash
set -euo pipefail

# setup-nutshell.sh — Install cashu-nutshell via pip (prebuilt wheels on PyPI)
# Usage: ./CI/setup-nutshell.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.nutshell-venv"

echo "🔧 Setting up Nutshell (pip install from PyPI)..."

# Create venv and install cashu-nutshell
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install cashu-nutshell

echo "✅ Nutshell installed via pip into ${VENV_DIR}"
echo "📦 Binary: ${VENV_DIR}/bin/nutshell"
