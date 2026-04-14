#!/bin/bash
################################################################################
# Test Runner Script for MTProxy
# License: MIT
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "MTProxy Test Suite"
echo -e "==========================================${NC}"

# Check if bats is installed
if ! command -v bats &>/dev/null; then
    echo -e "${YELLOW}Bats not found. Installing...${NC}"
    apt-get update -qq
    apt-get install -y -qq bats
fi

# Run tests
echo -e "\n${GREEN}Running tests...${NC}\n"

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

for test_file in "${TESTS_DIR}"/test_*.bats; do
    if [[ -f "$test_file" ]]; then
        TEST_COUNT=$((TEST_COUNT + 1))
        echo -e "${BLUE}Testing: $(basename "$test_file")${NC}"
        
        if bats "$test_file"; then
            PASS_COUNT=$((PASS_COUNT + 1))
            echo -e "${GREEN}✓ Passed${NC}\n"
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            echo -e "${RED}✗ Failed${NC}\n"
        fi
    fi
done

echo -e "${BLUE}=========================================="
echo -e "Test Summary"
echo -e "==========================================${NC}"
echo -e "Total test files: ${TEST_COUNT}"
echo -e "${GREEN}Passed: ${PASS_COUNT}${NC}"
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo -e "${RED}Failed: ${FAIL_COUNT}${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
