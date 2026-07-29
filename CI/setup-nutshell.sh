#!/bin/bash
set -euo pipefail

# setup-nutshell.sh — Install Nutshell (cashu) via pip (prebuilt wheels on PyPI)
# Usage: ./CI/setup-nutshell.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.nutshell-venv"

echo "🔧 Setting up Nutshell (pip install from PyPI)..."

# Cashu 0.20.x currently depends on native packages that do not build cleanly
# with the newest Python runtimes, so prefer a stable CI-compatible interpreter.
if [ -n "${PYTHON:-}" ]; then
    PYTHON_BIN="$PYTHON"
else
    PYTHON_BIN=""
    for candidate in python3.12 python3.11 python3.10; do
        if command -v "$candidate" >/dev/null 2>&1; then
            PYTHON_BIN="$candidate"
            break
        fi
    done
fi

if [ -z "${PYTHON_BIN}" ]; then
    echo "❌ No compatible Python found. Install Python 3.10-3.12 or set PYTHON=/path/to/python."
    exit 1
fi

PYTHON_VERSION="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
case "$PYTHON_VERSION" in
    3.10|3.11|3.12) ;;
    *)
        echo "❌ Unsupported Python ${PYTHON_VERSION}. Use Python 3.10, 3.11, or 3.12 for Nutshell."
        exit 1
        ;;
esac

if [ -d "$VENV_DIR" ]; then
    VENV_VERSION="$("$VENV_DIR/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
    if [ "$VENV_VERSION" != "$PYTHON_VERSION" ]; then
        echo "♻️  Recreating Nutshell venv with Python ${PYTHON_VERSION}..."
        rm -rf "$VENV_DIR"
    fi
fi

# Create venv and install Nutshell. The Cashu Nutshell mint is published to
# PyPI as the `cashu` package; it exposes the `mint` console script.
"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
# Exact mint and transitive-dependency pins required by cashu 0.20.1:
#   - cashu==0.20.1: this is the version validated with the app's pinned CDK
#     binding. Do not let the live UI boundary change underneath CI.
#   - marshmallow<4: cashu depends on environs<10, which breaks against
#     marshmallow 4.x (removed `__version_info__`) -> mint won't import.
#   - limits<4: cashu hardcodes the `fixed-window-elastic-expiry` rate-limit
#     strategy, removed in limits 4.x -> mint won't start.
"$VENV_DIR/bin/pip" install "marshmallow<4" "limits<4" "cashu==0.20.1"

echo "✅ Nutshell installed via pip into ${VENV_DIR}"
echo "📦 Binary: ${VENV_DIR}/bin/mint"
