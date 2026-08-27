#!/usr/bin/env bash
# Runs a Gradle Android UI test task with retries on transient emulator failures
# ("device offline", "Failed to retrieve additional test outputs from device", ...).
#
# When an attempt dies mid-run, the retry *resumes* the suite instead of
# restarting it: the emulator has been observed expiring at a deterministic
# point ~6 minutes into the managed-device suite, so a from-scratch retry just
# re-cooks the next emulator to the same crash. Classes recorded as passed in
# the Gradle test-result XML are excluded via the runner's notClass filter on
# the next attempt, and only the never-ran and failed classes re-run. A
# genuinely failing class is never excluded — it re-runs and still fails the
# build if it keeps failing.
#
# Usage: CI/retry-android-ui-test.sh <gradle command...>
# Env:   MAX_ATTEMPTS (default 3), LOG_FILE (default android-ui-test.log)
set -uo pipefail

MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
LOG_FILE="${LOG_FILE:-android-ui-test.log}"
TRANSIENT_PATTERN="device offline|Failed to retrieve additional test outputs|emulator: ERROR|INSTALL_FAILED_DEVICE|DEVICE_UNAVAILABLE|adb: device .* not found|Emulator.*crashed|Failed to (install|push).*device"
RESULTS_GLOB="app/build/outputs/androidTest-results/managedDevice/debug/*/TEST-*.xml"
if ! PASSED_CLASSES_FILE="$(mktemp "${TMPDIR:-/tmp}/android-ui-passed-classes.XXXXXX")"; then
  echo "Failed to create the passed-class ledger." >&2
  exit 1
fi
trap 'rm -f "$PASSED_CLASSES_FILE"' EXIT

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

# Unions every testsuite that completed without failures or errors into the
# passed-class ledger. Each Gradle run rewrites the XML, so it always reflects
# the latest attempt; the ledger accumulates across attempts. The class that
# was in flight when the device died is recorded with a failure, so it never
# lands here and always re-runs.
collect_passed_classes() {
  # shellcheck disable=SC2086
  grep -h '<testsuite ' $RESULTS_GLOB 2>/dev/null \
    | grep 'failures="0"' \
    | grep 'errors="0"' \
    | sed -E 's/^[[:space:]]*<testsuite name="([^"]+)".*/\1/' \
    >> "$PASSED_CLASSES_FILE" || true
  [ -s "$PASSED_CLASSES_FILE" ] && sort -u "$PASSED_CLASSES_FILE" -o "$PASSED_CLASSES_FILE"
}

attempt=1
extra_args=()
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
  echo "=== UI test attempt $attempt/$MAX_ATTEMPTS ==="

  # Ensure ADB is healthy and give the device layer time to settle before
  # Gradle Managed Devices boots the emulator for this attempt.
  reset_device_state
  sleep 10

  if [ -s "$PASSED_CLASSES_FILE" ]; then
    echo "Resuming: excluding $(wc -l < "$PASSED_CLASSES_FILE" | tr -d ' ') classes that already passed."
  fi
  # ${extra_args[@]+...} keeps bash 3.2 (macOS) happy under set -u when empty.
  "$@" ${extra_args[@]+"${extra_args[@]}"} 2>&1 | tee "$LOG_FILE"
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

  collect_passed_classes
  if [ -s "$PASSED_CLASSES_FILE" ]; then
    extra_args=("-Pandroid.testInstrumentationRunnerArguments.notClass=$(paste -sd, "$PASSED_CLASSES_FILE")")
  fi

  echo "Transient device failure detected (exit $status); resuming remaining tests after emulator reset..."
  attempt=$((attempt + 1))
done
