#!/bin/bash
# Test starter code locally - matches CI validate-starter-code job
# CI Workflow: .github/workflows/validate-exercises.yml lines 37-99

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Progress tracking
PROGRESS_FILE="$TMPDIR/progress.txt"
echo "0" > "$PROGRESS_FILE"

# Test single exercise matching CI starter validation
test_starter() {
    local exercise="$1"
    local tmpfile="$2"

    cd "$REPO_ROOT/$exercise"

    local exercise_name=$(basename "$exercise")
    local category=$(dirname "$exercise")

    echo "🔄 Testing $exercise..." >&2

    # Verify go.mod exists (CI line 64-71)
    if [ ! -f "go.mod" ]; then
        echo "  ❌ Missing go.mod" >&2
        echo "FAIL:$exercise:Missing go.mod" >> "$tmpfile"
        return 1
    fi

    # Download dependencies (CI line 73-77)
    echo "  📥 Downloading dependencies..." >&2
    if ! go mod download > /dev/null 2>&1; then
        echo "  ❌ Dependency download failed" >&2
        echo "FAIL:$exercise:Dependency download failed" >> "$tmpfile"
        return 1
    fi

    echo "  🔍 Verifying dependencies..." >&2
    if ! go mod verify > /dev/null 2>&1; then
        echo "  ❌ Dependency verification failed" >&2
        echo "FAIL:$exercise:Dependency verification failed" >> "$tmpfile"
        return 1
    fi

    # Compile starter code (CI line 79-87)
    echo "  🔨 Compiling starter code..." >&2
    if ! go build -v ./... > /dev/null 2>&1; then
        echo "  ❌ Compilation failed" >&2
        echo "FAIL:$exercise:Starter compilation failed" >> "$tmpfile"
        return 1
    fi

    # Run tests on starter code - expect failures (CI line 89-98)
    # Add timeout to prevent hanging on infinite loops or deadlocks
    echo "  🧪 Running tests (30s timeout)..." >&2
    if timeout 30s go test -v ./... > /dev/null 2>&1; then
        echo "  ⚠️  Tests passed (TODOs might be missing)" >&2
        echo "WARN:$exercise:Starter tests passed (TODOs might be missing)" >> "$tmpfile"
    elif [ $? -eq 124 ]; then
        echo "  ⏱️  Tests timed out (likely hanging/infinite loop)" >&2
        echo "WARN:$exercise:Tests timed out after 30s" >> "$tmpfile"
    fi

    echo "  ✅ Passed" >&2
    echo "PASS:$exercise" >> "$tmpfile"

    # Update progress counter
    local current=$(cat "$PROGRESS_FILE")
    echo $((current + 1)) > "$PROGRESS_FILE"

    return 0
}

export -f test_starter
export REPO_ROOT
export PROGRESS_FILE

# Find all exercises (CI line 29-32)
echo "🔍 Finding exercises..."
exercises=$(find . -type f -name "go.mod" -path "*/[0-9]*" | \
    sed 's|/go.mod||' | \
    sed 's|^\./||' | \
    sort)

exercise_count=$(echo "$exercises" | wc -l)

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  CI Starter Code Validation (Local)"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Testing $exercise_count exercises in parallel (8 concurrent)..."
echo "Each exercise: download deps → verify → compile → test"
echo ""
echo "⏱️  Estimated time: ~$((exercise_count * 3 / 8))s (with 8 parallel workers)"
echo ""

# Run tests in parallel (8 at a time like parallel-test.sh)
start_time=$(date +%s)

# Background progress monitor
(
    while true; do
        sleep 5
        completed=$(cat "$PROGRESS_FILE" 2>/dev/null || echo "0")
        if [ "$completed" -gt 0 ]; then
            echo "📊 Progress: $completed/$exercise_count exercises completed..." >&2
        fi
        # Check if parent process still exists
        if ! kill -0 $$ 2>/dev/null; then
            break
        fi
    done
) &
monitor_pid=$!

echo "$exercises" | xargs -P 8 -I {} bash -c "test_starter '{}' '$TMPDIR/results.txt'"

# Stop progress monitor
kill $monitor_pid 2>/dev/null
wait $monitor_pid 2>/dev/null

end_time=$(date +%s)
elapsed=$((end_time - start_time))

echo ""
echo "⏱️  Total time: ${elapsed}s"
echo ""

# Collect results
if [ -f "$TMPDIR/results.txt" ]; then
    passed=$(grep "^PASS:" "$TMPDIR/results.txt" | wc -l)
    failed=$(grep "^FAIL:" "$TMPDIR/results.txt" | cut -d: -f2-3 | sort)
    failed_count=$(echo "$failed" | grep -c .)
    warnings=$(grep "^WARN:" "$TMPDIR/results.txt" | cut -d: -f2-3 | sort)
    warn_count=$(echo "$warnings" | grep -c .)

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "RESULTS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ $failed_count -gt 0 ]; then
        echo -e "${RED}❌ FAILED ($failed_count):${NC}"
        echo "$failed" | sed 's/^/  - /' | sed "s/:/ - /"
        echo ""
    fi

    if [ $warn_count -gt 0 ]; then
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
    echo ""

    if [ $failed_count -eq 0 ]; then
        echo -e "${GREEN}✅ All starter code validations passed${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some starter validations failed${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ No exercises found or all passed${NC}"
    exit 0
fi
