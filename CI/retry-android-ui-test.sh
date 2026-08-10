#!/usr/bin/env bash
# Runs a Gradle Android UI test task with retries on transient emulator failures
# ("device offline", "Failed to retrieve additional test outputs from device", ...).
#
# Usage: CI/retry-android-ui-test.sh <gradle command...>
# Env:   MAX_ATTEMPTS (default 3), LOG_FILE (default android-ui-test.log)
set -uo pipefail

MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
LOG_FILE="${LOG_FILE:-android-ui-test.log}"
TRANSIENT_PATTERN="device offline|Failed to retrieve additional test outputs|emulator: ERROR|INSTALL_FAILED_DEVICE|DEVICE_UNAVAILABLE|adb: device .* not found|Emulator.*crashed|Failed to (install|push).*device"

reset_device_state() {
  echo "Resetting ADB/emulator state..."
  pkill -f "qemu-system" 2>/dev/null || true
  pkill -f "crashpad_handler" 2>/dev/null || true
  adb kill-server 2>/dev/null || true
  sleep 5
  adb start-server 2>/dev/null || true
  sleep 5
  adb devices || true
}

attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
  echo "=== UI test attempt $attempt/$MAX_ATTEMPTS ==="

  # Ensure ADB is healthy and give the device layer time to settle before
  # Gradle Managed Devices boots the emulator for this attempt.
  reset_device_state
  sleep 10

  "$@" 2>&1 | tee "$LOG_FILE"
  status=${PIPESTATUS[0]}

  if [ "$status" -eq 0 ]; then
    echo "UI tests passed on attempt $attempt."
    exit 0
  fi

  if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    echo "UI tests failed after $MAX_ATTEMPTS attempts."
    exit "$status"
  fi

  if ! grep -qE "$TRANSIENT_PATTERN" "$LOG_FILE"; then
    echo "Failure does not match a known transient device error; not retrying."
    exit "$status"
  fi

  echo "Transient device failure detected (exit $status); retrying after emulator reset..."
  attempt=$((attempt + 1))
done
