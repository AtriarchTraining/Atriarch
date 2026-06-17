#!/usr/bin/env bash
# Verifies the 6 safety-critical signatures from commit e7f926b still exist.
# Run after any change that touches screens/program_*, drill_running_screen,
# services/ble_service, or state/app_state.

set -e
cd "$(git rev-parse --show-toplevel)"
fail=0
check() {
  local description=$1
  local pattern=$2
  local path=$3
  if ! grep -q -E "$pattern" "$path"; then
    echo "MISSING: $description  (pattern: $pattern in $path)"
    fail=1
  else
    echo "OK     : $description"
  fi
}

check "STOP-flood guard" \
  '_phase != DrillPhase\.running && _phase != DrillPhase\.arming' \
  lib/state/app_state.dart

check "BLE UUID str128 service" \
  'service\.uuid\.str128\.toLowerCase\(\)' \
  lib/services/ble_service.dart

check "BLE UUID str128 characteristic" \
  'char\.uuid\.str128\.toLowerCase\(\)' \
  lib/services/ble_service.dart

check "Program A nav listener detach" \
  'removeListener\(_onPhaseChanged\)' \
  lib/screens/program_a_setup_screen.dart

check "Program B nav listener detach" \
  'removeListener\(_onPhaseChanged\)' \
  lib/screens/program_b_setup_screen.dart

check "Drill-running nav listener detach" \
  'removeListener\(_checkDrillComplete\)' \
  lib/screens/drill_running_screen.dart

check "8s scan timeout" \
  'Timer\(const Duration\(seconds: 8\)' \
  lib/state/app_state.dart

check "SNAP/ send on reconnect" \
  'encodeSnap\(\)' \
  lib/state/app_state.dart

check "800ms STOP hold" \
  'Duration\(milliseconds: 800\)' \
  lib/screens/drill_running_screen.dart

check "PopScope canPop:false on drill screen" \
  'canPop: false' \
  lib/screens/drill_running_screen.dart

check "Program B scan entry (discoverTargets call)" \
  'state\.discoverTargets\(\)' \
  lib/screens/program_b_setup_screen.dart

if [ $fail -eq 1 ]; then
  echo
  echo "FAIL: one or more safety-critical signatures missing. Re-port from e7f926b."
  exit 1
fi

echo
echo "All 11 signatures present."
