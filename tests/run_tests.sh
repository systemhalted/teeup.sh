#!/usr/bin/env bash
# run_tests.sh — Run all tests
#
# Usage: ./tests/run_tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Mac Setup - Test Suite                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Make test scripts executable
chmod +x "$SCRIPT_DIR/test_setup_mac.sh"
chmod +x "$SCRIPT_DIR/test_setup_wizard.sh"

TOTAL_PASSED=0
TOTAL_FAILED=0

# Run setup_mac.sh tests
echo "━��━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPT_DIR/test_setup_mac.sh" && MAC_RESULT=0 || MAC_RESULT=$?
echo ""

# Run setup_wizard.sh tests
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPT_DIR/test_setup_wizard.sh" && WIZARD_RESULT=0 || WIZARD_RESULT=$?
echo ""

# Overall summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Overall Results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $MAC_RESULT -eq 0 ]]; then
  echo -e "  setup_mac.sh tests:    \033[0;32mPASSED\033[0m"
else
  echo -e "  setup_mac.sh tests:    \033[0;31mFAILED\033[0m"
fi

if [[ $WIZARD_RESULT -eq 0 ]]; then
  echo -e "  setup_wizard.sh tests: \033[0;32mPASSED\033[0m"
else
  echo -e "  setup_wizard.sh tests: \033[0;31mFAILED\033[0m"
fi

echo ""

if [[ $MAC_RESULT -eq 0 && $WIZARD_RESULT -eq 0 ]]; then
  echo -e "\033[0;32m✅ All tests passed!\033[0m"
  exit 0
else
  echo -e "\033[0;31m❌ Some tests failed!\033[0m"
  exit 1
fi
