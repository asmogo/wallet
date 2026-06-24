#!/bin/bash

# Cleanup script for CI integration tests
# Removes temporary files and directories created during testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧹 Cleaning up CI test environment..."

# Stop any running mints
if [ -f "$SCRIPT_DIR/stop-nutshell.sh" ]; then
    bash "$SCRIPT_DIR/stop-nutshell.sh" 2>/dev/null || true
fi

if [ -f "$SCRIPT_DIR/stop-cdk.sh" ]; then
    bash "$SCRIPT_DIR/stop-cdk.sh" 2>/dev/null || true
fi

# Clean up temporary test databases
echo "Removing temporary test databases..."
rm -f /tmp/cashu_test_*.db 2>/dev/null || true
rm -rf /tmp/cashu_integration_tests_* 2>/dev/null || true

# Clean up mint data directories
if [ -d "$SCRIPT_DIR/.mint-data" ]; then
    echo "Removing mint data directory..."
    rm -rf "$SCRIPT_DIR/.mint-data" 2>/dev/null || true
fi

# Clean up logs
if [ -d "$SCRIPT_DIR/logs" ]; then
    echo "Removing log files..."
    rm -rf "$SCRIPT_DIR/logs" 2>/dev/null || true
fi

# Clean up Xcode build artifacts if running in CI
if [ "$CI" = "true" ] || [ "$GITHUB_ACTIONS" = "true" ]; then
    echo "Cleaning Xcode build artifacts..."
    if [ -d "build" ]; then
        rm -rf build 2>/dev/null || true
    fi
fi

# Clean up Swift package cache if needed
if [ -d ".build" ]; then
    echo "Note: Keeping .build directory for faster rebuilds"
fi

echo "✅ Cleanup complete!"
