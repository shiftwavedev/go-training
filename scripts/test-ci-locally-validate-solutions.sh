#!/bin/bash
# Test solutions locally - matches CI validate-solutions job
# CI Workflow: .github/workflows/validate-exercises.yml lines 100-172

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Verbose mode flag
VERBOSE="${VERBOSE:-0}"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Test single exercise solution matching CI solution validation
test_solution() {
    local exercise="$1"
    local tmpfile="$2"

    cd "$REPO_ROOT/$exercise"

    local exercise_name=$(basename "$exercise")
    local category=$(dirname "$exercise")

    # Check if solution exists (CI line 119-128)
    if [ ! -f "solution/main.go" ]; then
        echo "SKIP:$exercise:No solution found" >> "$tmpfile"
        return 0
    fi

    # Backup starter code
    cp main.go main.go.backup 2>/dev/null

    # Copy solution
    cp solution/main.go main.go 2>/dev/null

    # Test solution (CI line 130-151)
    if [ "$VERBOSE" = "1" ]; then
        # Verbose mode - show actual test output for debugging
        if ! go test -v -cover ./... 2>&1 | tee "$TMPDIR/${exercise//\//_}_test.log"; then
            echo "FAIL:$exercise:Solution tests failed" >> "$tmpfile"
            mv main.go.backup main.go 2>/dev/null
            return 1
        fi
    else
        # Silent mode - just check pass/fail
        if ! go test -v -cover ./... > /dev/null 2>&1; then
            echo "FAIL:$exercise:Solution tests failed" >> "$tmpfile"
            mv main.go.backup main.go 2>/dev/null
            return 1
        fi
    fi

    # Run race detector for concurrency exercises (CI line 153-172)
    if [[ "$exercise" == *"concurrency"* ]]; then
        if [ "$VERBOSE" = "1" ]; then
            # Verbose mode - show race detector output
            if ! go test -race -short -v ./... 2>&1 | tee "$TMPDIR/${exercise//\//_}_race.log"; then
                echo "FAIL:$exercise:Race conditions detected" >> "$tmpfile"
                mv main.go.backup main.go 2>/dev/null
                return 1
            fi
        else
            # Silent mode - just check pass/fail
            if ! go test -race -short -v ./... > /dev/null 2>&1; then
                echo "FAIL:$exercise:Race conditions detected" >> "$tmpfile"
                mv main.go.backup main.go 2>/dev/null
                return 1
            fi
        fi
    fi

    # Check solution documentation (CI line 174-181)
    if [ ! -f "solution/EXPLANATION.md" ]; then
        echo "WARN:$exercise:Missing EXPLANATION.md" >> "$tmpfile"
    fi

    # Restore starter code
    mv main.go.backup main.go 2>/dev/null

    echo "PASS:$exercise" >> "$tmpfile"
    return 0
}

export -f test_solution
export REPO_ROOT
export VERBOSE
export TMPDIR

# Find all exercises (CI line 29-32)
echo "🔍 Finding exercises..."
exercises=$(find . -type f -name "go.mod" -path "*/[0-9]*" | \
    sed 's|/go.mod||' | \
    sed 's|^\./||' | \
    sort)

exercise_count=$(echo "$exercises" | wc -l)

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  CI Solution Validation (Local)"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Testing $exercise_count exercises in parallel..."
if [ "$VERBOSE" = "1" ]; then
    echo -e "${YELLOW}Verbose mode: Will show detailed test output for failures${NC}"
fi
echo ""

# Run tests in parallel (8 at a time like parallel-test.sh)
echo "$exercises" | xargs -P 8 -I {} bash -c "test_solution '{}' '$TMPDIR/results.txt'"

# Collect results
if [ -f "$TMPDIR/results.txt" ]; then
    passed=$(grep "^PASS:" "$TMPDIR/results.txt" | wc -l)
    failed=$(grep "^FAIL:" "$TMPDIR/results.txt" | cut -d: -f2-3 | sort)
    failed_count=$(grep "^FAIL:" "$TMPDIR/results.txt" | wc -l)
    warnings=$(grep "^WARN:" "$TMPDIR/results.txt" | cut -d: -f2-3 | sort)
    warn_count=$(grep "^WARN:" "$TMPDIR/results.txt" | wc -l)
    skipped=$(grep "^SKIP:" "$TMPDIR/results.txt" | wc -l)

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "RESULTS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ "$failed_count" -gt 0 ]; then
        echo -e "${RED}❌ FAILED ($failed_count):${NC}"
        echo "$failed" | sed 's/^/  - /' | sed "s/:/ - /"
        echo ""

        # If verbose mode, show log file locations
        if [ "$VERBOSE" = "1" ]; then
            echo -e "${BLUE}Detailed logs available in: $TMPDIR/${NC}"
            for ex in $(echo "$failed" | cut -d: -f1); do
                logfile="$TMPDIR/${ex//\//_}_test.log"
                racelog="$TMPDIR/${ex//\//_}_race.log"
                [ -f "$logfile" ] && echo "  - $logfile"
                [ -f "$racelog" ] && echo "  - $racelog"
            done
            echo ""
        fi
    fi

    if [ "$warn_count" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  WARNINGS ($warn_count):${NC}"
        echo "$warnings" | sed 's/^/  - /' | sed "s/:/ - /"
        echo ""
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Total:    $exercise_count"
    echo -e "Passed:   ${GREEN}$passed${NC}"
    echo -e "Failed:   ${RED}$failed_count${NC}"
    echo -e "Warnings: ${YELLOW}$warn_count${NC}"
    echo -e "Skipped:  ${BLUE}$skipped${NC} (no solution)"
    echo ""

    # Save failed exercises to file for easy reference
    if [ "$failed_count" -gt 0 ]; then
        echo "$failed" | cut -d: -f1 > "$REPO_ROOT/failing_solutions.txt"
        echo -e "${BLUE}Failed exercises saved to: failing_solutions.txt${NC}"
        echo ""
    fi

    if [ "$failed_count" -eq 0 ]; then
        echo -e "${GREEN}✅ All solution validations passed${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some solution validations failed${NC}"
        echo -e "${YELLOW}Tip: Run with VERBOSE=1 to see detailed test output${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ No exercises found or all passed${NC}"
    exit 0
fi
