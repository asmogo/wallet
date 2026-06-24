#!/bin/bash
set -euo pipefail

# setup-nutshell.sh — Install Nutshell (cashu) via pip (prebuilt wheels on PyPI)
# Usage: ./CI/setup-nutshell.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.nutshell-venv"

echo "🔧 Setting up Nutshell (pip install from PyPI)..."

# Create venv and install Nutshell. The Cashu Nutshell mint is published to
# PyPI as the `cashu` package; it exposes the `mint` console script.
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
# Transitive-dependency pins required by cashu 0.20.1:
#   - marshmallow<4: cashu depends on environs<10, which breaks against
#     marshmallow 4.x (removed `__version_info__`) -> mint won't import.
#   - limits<4: cashu hardcodes the `fixed-window-elastic-expiry` rate-limit
#     strategy, removed in limits 4.x -> mint won't start.
"$VENV_DIR/bin/pip" install "marshmallow<4" "limits<4" cashu

echo "✅ Nutshell installed via pip into ${VENV_DIR}"
echo "📦 Binary: ${VENV_DIR}/bin/mint"
