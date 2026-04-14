#!/bin/bash
################################################################################
# Test Runner Script for MTProxy
# License: MIT
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo -e "MTProxy Test Suite"
echo -e "==========================================${NC}"

RUN_SYNTAX=true
RUN_SMOKE=true
RUN_BATS=true
INSTALL_BATS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --syntax-only)
            RUN_SYNTAX=true
            RUN_SMOKE=false
            RUN_BATS=false
            ;;
        --no-smoke)
            RUN_SMOKE=false
            ;;
        --no-bats)
            RUN_BATS=false
            ;;
        --install-bats)
            INSTALL_BATS=true
            ;;
        -h|--help)
            cat << EOF
Usage: $0 [options]

Options:
  --syntax-only   Run only bash syntax checks
  --no-smoke      Skip smoke checks for CLI help/version
  --no-bats       Skip Bats test suites
  --install-bats  Try to install bats if missing
  -h, --help      Show this help
EOF
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
    shift
done

run_check() {
    local description="$1"
    shift
    if "$@"; then
        echo -e "${GREEN}✓ ${description}${NC}"
        return 0
    fi

    echo -e "${RED}✗ ${description}${NC}"
    return 1
}

FAIL_COUNT=0

if [[ "$RUN_SYNTAX" == "true" ]]; then
    echo -e "\n${GREEN}Running syntax checks...${NC}"
    if ! run_check "bash -n for project scripts" \
        bash -n "${ROOT_DIR}/scripts/mtproxy-cli.sh" "${ROOT_DIR}/src/utils.sh" "${ROOT_DIR}/src/firewall.sh" "${ROOT_DIR}/src/docker.sh" "${ROOT_DIR}/src/secrets.sh"; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

if [[ "$RUN_SMOKE" == "true" ]]; then
    echo -e "\n${GREEN}Running smoke checks...${NC}"
    if ! run_check "CLI help output" bash -c "'${ROOT_DIR}/scripts/mtproxy-cli.sh' --help >/dev/null"; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    if ! run_check "CLI version output" bash -c "'${ROOT_DIR}/scripts/mtproxy-cli.sh' --version >/dev/null"; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

if [[ "$RUN_BATS" == "true" ]]; then
    # Check if bats is installed
    if ! command -v bats &>/dev/null; then
        if [[ "$INSTALL_BATS" == "true" ]]; then
            echo -e "${YELLOW}Bats not found. Installing...${NC}"
            apt-get update -qq && apt-get install -y -qq bats
        else
            echo -e "${YELLOW}Bats not found. Skipping Bats tests (use --install-bats to auto-install).${NC}"
            RUN_BATS=false
        fi
    fi
fi

if [[ "$RUN_BATS" == "true" ]]; then
    # Run bats tests
    echo -e "\n${GREEN}Running Bats tests...${NC}\n"

    TEST_COUNT=0
    PASS_COUNT=0

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

    echo -e "Bats test files: ${TEST_COUNT}"
    echo -e "${GREEN}Bats passed: ${PASS_COUNT}${NC}"
fi

echo -e "${BLUE}=========================================="
echo -e "Test Summary"
echo -e "==========================================${NC}"
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo -e "${RED}Failed: ${FAIL_COUNT}${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
