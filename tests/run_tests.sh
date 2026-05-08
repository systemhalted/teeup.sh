#!/usr/bin/env bash
# run_tests.sh — Run all tests
#
# Usage: ./tests/run_tests.sh

set -euo pipefail

if [[ "${LC_ALL:-}" == "C.UTF-8" || "${LANG:-}" == "C.UTF-8" ]]; then
  export LANG="en_US.UTF-8"
  export LC_ALL="en_US.UTF-8"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              teeup - Test Suite                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Make test scripts executable
chmod +x "$SCRIPT_DIR/test_teeup.sh"
chmod +x "$SCRIPT_DIR/test_teeup_wizard.sh"
chmod +x "$SCRIPT_DIR/test_teeup_behavior.sh"

TOTAL_PASSED=0
TOTAL_FAILED=0

# Run teeup.sh tests
echo "━��━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPT_DIR/test_teeup.sh" && MAC_RESULT=0 || MAC_RESULT=$?
echo ""

# Run teeup.sh behavioral tests
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPT_DIR/test_teeup_behavior.sh" && BEHAVIOR_RESULT=0 || BEHAVIOR_RESULT=$?
echo ""

# Run teeup-wizard.sh tests
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPT_DIR/test_teeup_wizard.sh" && WIZARD_RESULT=0 || WIZARD_RESULT=$?
echo ""

# Overall summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Overall Results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $MAC_RESULT -eq 0 ]]; then
  echo -e "  teeup.sh tests:    \033[0;32mPASSED\033[0m"
else
  echo -e "  teeup.sh tests:    \033[0;31mFAILED\033[0m"
fi

if [[ $BEHAVIOR_RESULT -eq 0 ]]; then
  echo -e "  behavior tests:    \033[0;32mPASSED\033[0m"
else
  echo -e "  behavior tests:    \033[0;31mFAILED\033[0m"
fi

if [[ $WIZARD_RESULT -eq 0 ]]; then
  echo -e "  teeup-wizard.sh tests: \033[0;32mPASSED\033[0m"
else
  echo -e "  teeup-wizard.sh tests: \033[0;31mFAILED\033[0m"
fi

echo ""

if [[ $MAC_RESULT -eq 0 && $BEHAVIOR_RESULT -eq 0 && $WIZARD_RESULT -eq 0 ]]; then
  echo -e "\033[0;32m✅ All tests passed!\033[0m"
  exit 0
else
  echo -e "\033[0;31m❌ Some tests failed!\033[0m"
  exit 1
fi
