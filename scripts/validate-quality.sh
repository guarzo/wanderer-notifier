#!/usr/bin/env bash
# Validate all quality gates before committing.
# Usage: ./scripts/validate-quality.sh
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

run_gate() {
  local name="$1"
  shift
  echo -e "${YELLOW}>>> ${name}${NC}"
  if "$@"; then
    echo -e "${GREEN}  PASS: ${name}${NC}\n"
    ((PASS++))
  else
    echo -e "${RED}  FAIL: ${name}${NC}\n"
    ((FAIL++))
  fi
}

echo "==============================="
echo " Quality Gate Validation"
echo "==============================="
echo ""

run_gate "Compile"          mix compile
run_gate "Tests"            mix test
run_gate "Credo (strict)"   mix credo --strict
run_gate "Dialyzer"         bash -c "MIX_ENV=dev mix dialyzer"

echo "==============================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}Quality gates FAILED. Fix issues before committing.${NC}"
  exit 1
else
  echo -e "${GREEN}All quality gates passed.${NC}"
  exit 0
fi
