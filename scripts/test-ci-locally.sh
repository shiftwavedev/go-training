#!/bin/bash
# Main CI orchestrator - runs both starter and solution validation
# Matches CI workflow: .github/workflows/validate-exercises.yml
#
# Usage:
#   ./scripts/test-ci-locally.sh              # Run both validations
#   ./scripts/test-ci-locally.sh --starter    # Run only starter validation
#   ./scripts/test-ci-locally.sh --solutions  # Run only solutions validation
#   VERBOSE=1 ./scripts/test-ci-locally.sh    # Run with verbose output

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse flags
RUN_STARTER=1
RUN_SOLUTIONS=1

if [ "$1" = "--starter" ]; then
    RUN_SOLUTIONS=0
elif [ "$1" = "--solutions" ]; then
    RUN_STARTER=0
elif [ -n "$1" ]; then
    echo "Usage: $0 [--starter|--solutions]"
    echo ""
    echo "Options:"
    echo "  --starter     Run only starter code validation"
    echo "  --solutions   Run only solutions validation"
    echo "  (no flag)     Run both validations (default)"
    echo ""
    echo "Environment variables:"
    echo "  VERBOSE=1     Show detailed test output"
    exit 1
fi

# Export verbose mode for sub-scripts
export VERBOSE="${VERBOSE:-0}"

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║       Local CI Validation Test Suite                  ║"
echo "║  Matches: .github/workflows/validate-exercises.yml    ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

if [ "$VERBOSE" = "1" ]; then
    echo -e "${YELLOW}Running in verbose mode${NC}"
    echo ""
fi

OVERALL_EXIT=0

# Run starter code validation (CI job 1)
if [ "$RUN_STARTER" = "1" ]; then
    echo -e "${CYAN}┌───────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ Job 1: Validate Starter Code                          │${NC}"
    echo -e "${CYAN}│ Matches: validate-starter-code (lines 37-99)          │${NC}"
    echo -e "${CYAN}└───────────────────────────────────────────────────────┘${NC}"
    echo ""

    if "$SCRIPT_DIR/test-ci-locally-starter-code.sh"; then
        echo ""
        echo -e "${GREEN}✅ Starter code validation passed${NC}"
    else
        echo ""
        echo -e "${RED}❌ Starter code validation failed${NC}"
        OVERALL_EXIT=1
    fi
fi

echo ""

# Run solutions validation (CI job 2)
if [ "$RUN_SOLUTIONS" = "1" ]; then
    echo -e "${CYAN}┌───────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ Job 2: Validate Solutions                             │${NC}"
    echo -e "${CYAN}│ Matches: validate-solutions (lines 100-172)           │${NC}"
    echo -e "${CYAN}└───────────────────────────────────────────────────────┘${NC}"
    echo ""

    if "$SCRIPT_DIR/test-ci-locally-validate-solutions.sh"; then
        echo ""
        echo -e "${GREEN}✅ Solutions validation passed${NC}"
    else
        echo ""
        echo -e "${RED}❌ Solutions validation failed${NC}"
        OVERALL_EXIT=1
    fi
fi

# Final summary
echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║                 Overall Results                        ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

if [ "$OVERALL_EXIT" -eq 0 ]; then
    echo -e "${GREEN}✅ All CI validations passed!${NC}"
    echo ""
    echo "Your changes are ready to push to CI."
else
    echo -e "${RED}❌ Some CI validations failed${NC}"
    echo ""
    echo "Fix the issues above before pushing to CI."
    echo ""
    if [ "$VERBOSE" != "1" ]; then
        echo -e "${YELLOW}Tip: Run with VERBOSE=1 for detailed error output:${NC}"
        echo "  VERBOSE=1 ./scripts/test-ci-locally.sh"
    fi
fi

echo ""

exit $OVERALL_EXIT
