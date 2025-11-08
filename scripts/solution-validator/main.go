package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/charmbracelet/lipgloss"
)

var (
	successStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("10")).Bold(true)
	failStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("9")).Bold(true)
	warnStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("11")).Bold(true)
	dimStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("8"))
	titleStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("12")).Bold(true)
)

type TestResult struct {
	Exercise string
	Status   string // "pass", "fail", "warn"
	Message  string
	Logs     []string
	Duration time.Duration
}

type SolutionTester struct {
	repoRoot string
	printMu  sync.Mutex
}

func NewSolutionTester(repoRoot string) *SolutionTester {
	return &SolutionTester{
		repoRoot: repoRoot,
	}
}

func (st *SolutionTester) printResult(result TestResult) {
	st.printMu.Lock()
	defer st.printMu.Unlock()

	if result.Status == "pass" {
		// Success: single line
		fmt.Println(successStyle.Render("✅") + " " + result.Exercise)
	} else {
		// Failure/Warning: show all logs
		for _, log := range result.Logs {
			fmt.Println(log)
		}
		if result.Status == "fail" {
			fmt.Println(failStyle.Render(fmt.Sprintf("  ❌ %s: %s", result.Exercise, result.Message)))
		} else if result.Status == "warn" {
			fmt.Println(warnStyle.Render(fmt.Sprintf("  ⚠️  %s: %s", result.Exercise, result.Message)))
		}
		fmt.Println()
	}
}

func (st *SolutionTester) testSolution(exercise string) TestResult {
	start := time.Now()
	result := TestResult{
		Exercise: exercise,
		Logs:     make([]string, 0),
	}

	// Solution is in exercise/solution/
	solutionPath := filepath.Join(st.repoRoot, exercise, "solution")

	// Log progress
	result.Logs = append(result.Logs, fmt.Sprintf("🔄 Testing %s/solution...", exercise))

	// Check solution directory exists
	if _, err := os.Stat(solutionPath); os.IsNotExist(err) {
		result.Status = "fail"
		result.Message = "Missing solution directory"
		result.Logs = append(result.Logs, "  ❌ solution/ directory not found")
		result.Duration = time.Since(start)
		return result
	}

	// Check go.mod exists
	if _, err := os.Stat(filepath.Join(solutionPath, "go.mod")); os.IsNotExist(err) {
		result.Status = "fail"
		result.Message = "Missing go.mod in solution"
		result.Logs = append(result.Logs, "  ❌ Missing go.mod")
		result.Duration = time.Since(start)
		return result
	}

	// Check EXPLANATION.md exists
	if _, err := os.Stat(filepath.Join(solutionPath, "EXPLANATION.md")); os.IsNotExist(err) {
		result.Status = "warn"
		result.Message = "Missing EXPLANATION.md"
		result.Logs = append(result.Logs, "  ⚠️  Missing EXPLANATION.md")
		// Continue validation even if EXPLANATION.md is missing
	}

	// Download dependencies
	result.Logs = append(result.Logs, "  📥 Downloading dependencies...")
	cmd := exec.Command("go", "mod", "download")
	cmd.Dir = solutionPath
	if err := cmd.Run(); err != nil {
		result.Status = "fail"
		result.Message = "Dependency download failed"
		result.Logs = append(result.Logs, "  ❌ Dependency download failed")
		result.Duration = time.Since(start)
		return result
	}

	// Verify dependencies
	result.Logs = append(result.Logs, "  🔍 Verifying dependencies...")
	cmd = exec.Command("go", "mod", "verify")
	cmd.Dir = solutionPath
	if err := cmd.Run(); err != nil {
		result.Status = "fail"
		result.Message = "Dependency verification failed"
		result.Logs = append(result.Logs, "  ❌ Dependency verification failed")
		result.Duration = time.Since(start)
		return result
	}

	// Compile solution code
	result.Logs = append(result.Logs, "  🔨 Compiling solution code...")
	cmd = exec.Command("go", "build", "-v", "./...")
	cmd.Dir = solutionPath
	output, err := cmd.CombinedOutput()
	if err != nil {
		result.Status = "fail"
		result.Message = "Solution compilation failed"
		result.Logs = append(result.Logs, "  ❌ Compilation failed")
		if len(output) > 0 {
			result.Logs = append(result.Logs, "")
			result.Logs = append(result.Logs, "Compilation output:")
			result.Logs = append(result.Logs, string(output))
		}
		result.Duration = time.Since(start)
		return result
	}

	// Determine if we need race detection (concurrency exercises)
	isConcurrencyExercise := strings.Contains(exercise, "concurrency")
	testArgs := []string{"test", "-v"}
	if isConcurrencyExercise {
		testArgs = append(testArgs, "-race")
	}
	testArgs = append(testArgs, "./...")

	// Run tests with timeout (with race detection for concurrency if needed)
	if isConcurrencyExercise {
		result.Logs = append(result.Logs, "  🧪 Running tests with race detector (30s timeout)...")
	} else {
		result.Logs = append(result.Logs, "  🧪 Running tests (30s timeout)...")
	}

	cmd = exec.Command("go", testArgs...)
	cmd.Dir = solutionPath

	// Set timeout
	done := make(chan error, 1)
	go func() {
		output, err := cmd.CombinedOutput()
		// If test output shows race condition, mark as error
		if err == nil && isConcurrencyExercise && strings.Contains(string(output), "race detected") {
			done <- fmt.Errorf("race condition detected")
		} else {
			done <- err
		}
	}()

	select {
	case err := <-done:
		if err == nil {
			// Tests passed - required for solution
			result.Status = "pass"
			result.Message = ""
		} else {
			// Tests failed - this is a failure for solution
			result.Status = "fail"
			result.Message = "Tests failed"
			if strings.Contains(err.Error(), "race") {
				result.Message = "Race condition detected"
			}
			result.Logs = append(result.Logs, fmt.Sprintf("  ❌ %s", result.Message))
		}
	case <-time.After(30 * time.Second):
		cmd.Process.Kill()
		result.Status = "fail"
		result.Message = "Tests timed out after 30s"
		result.Logs = append(result.Logs, "  ❌ Tests timed out (likely hanging/infinite loop)")
	}

	result.Duration = time.Since(start)
	return result
}

func findSolutions(repoRoot string) ([]string, error) {
	solutions := make([]string, 0)

	// Expected top-level directories for exercises
	validPrefixes := []string{"basics", "intermediate", "advanced", "concurrency", "projects"}

	err := filepath.Walk(repoRoot, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Skip unwanted directories
		if info.IsDir() {
			name := info.Name()
			relPath, _ := filepath.Rel(repoRoot, path)

			// Skip backup, vendor, hidden dirs, scripts, bin, etc.
			if strings.Contains(name, "backup") || name == "vendor" ||
				name == ".git" || strings.HasPrefix(name, ".") ||
				name == "bin" || name == "scripts" || name == "claudedocs" {
				return filepath.SkipDir
			}

			// Skip if not under a valid prefix
			if relPath != "." {
				parts := strings.Split(relPath, string(filepath.Separator))
				if len(parts) > 0 {
					isValid := false
					for _, prefix := range validPrefixes {
						if parts[0] == prefix {
							isValid = true
							break
						}
					}
					if !isValid {
						return filepath.SkipDir
					}
				}
			}
		}

		if info.Name() == "go.mod" {
			relPath, err := filepath.Rel(repoRoot, filepath.Dir(path))
			if err != nil {
				return err
			}

			// Only include SOLUTION directories (opposite of starter validator)
			if !strings.Contains(relPath, "solution") {
				return nil
			}

			// Extract exercise path (remove /solution suffix)
			exercisePath := filepath.Dir(relPath)
			if filepath.Base(exercisePath) == "solution" {
				exercisePath = filepath.Dir(exercisePath)
			}

			// Only include paths with numbers (exercise directories)
			parts := strings.Split(exercisePath, string(filepath.Separator))
			for _, part := range parts {
				if len(part) > 0 && part[0] >= '0' && part[0] <= '9' {
					solutions = append(solutions, exercisePath)
					break
				}
			}
		}

		return nil
	})

	sort.Strings(solutions)
	return solutions, err
}

func main() {
	// When running from scripts/solution-validator, go up two levels to project root
	repoRoot := filepath.Join("..", "..")
	if len(os.Args) > 1 {
		repoRoot = os.Args[1]
	}

	absRoot, err := filepath.Abs(repoRoot)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error resolving repo root: %v\n", err)
		os.Exit(1)
	}

	fmt.Println()
	fmt.Println(titleStyle.Render("═══════════════════════════════════════════════════════"))
	fmt.Println(titleStyle.Render("  CI Solution Code Validation (Go Edition)"))
	fmt.Println(titleStyle.Render("═══════════════════════════════════════════════════════"))
	fmt.Println()

	// Find solutions
	fmt.Println(dimStyle.Render("🔍 Finding solutions..."))
	solutions, err := findSolutions(absRoot)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error finding solutions: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("\nTesting %s solutions in parallel (10 concurrent)...\n",
		titleStyle.Render(fmt.Sprintf("%d", len(solutions))))
	fmt.Println(dimStyle.Render("Each solution: download deps → verify → compile → test (+ race check for concurrency)"))
	fmt.Println()

	startTime := time.Now()

	// Run tests concurrently
	tester := NewSolutionTester(absRoot)
	results := make(chan TestResult, len(solutions))
	semaphore := make(chan struct{}, 10) // 10 concurrent workers

	var wg sync.WaitGroup
	for _, solution := range solutions {
		wg.Add(1)
		go func(sol string) {
			defer wg.Done()
			semaphore <- struct{}{}        // Acquire
			defer func() { <-semaphore }() // Release

			result := tester.testSolution(sol)
			results <- result

			// Print result immediately (synchronized)
			tester.printResult(result)
		}(solution)
	}

	// Wait for all tests to complete
	go func() {
		wg.Wait()
		close(results)
	}()

	// Collect results
	allResults := make([]TestResult, 0, len(solutions))
	for result := range results {
		allResults = append(allResults, result)
	}

	elapsed := time.Since(startTime)

	// Print summary
	fmt.Println()
	fmt.Println(titleStyle.Render("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"))
	fmt.Println(titleStyle.Render("SUMMARY"))
	fmt.Println(titleStyle.Render("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"))
	fmt.Println()

	passed := 0
	failed := 0
	warned := 0
	failedExercises := make([]TestResult, 0)
	warnedExercises := make([]TestResult, 0)

	for _, result := range allResults {
		switch result.Status {
		case "pass":
			passed++
		case "fail":
			failed++
			failedExercises = append(failedExercises, result)
		case "warn":
			warned++
			warnedExercises = append(warnedExercises, result)
		}
	}

	// Show failures
	if failed > 0 {
		fmt.Println(failStyle.Render(fmt.Sprintf("❌ FAILED (%d):", failed)))
		for _, result := range failedExercises {
			fmt.Printf("  - %s - %s\n", result.Exercise, result.Message)
		}
		fmt.Println()
	}

	// Show warnings
	if warned > 0 {
		fmt.Println(warnStyle.Render(fmt.Sprintf("⚠️  WARNINGS (%d):", warned)))
		for _, result := range warnedExercises {
			fmt.Printf("  - %s - %s\n", result.Exercise, result.Message)
		}
		fmt.Println()
	}

	fmt.Printf("Total:    %d\n", len(solutions))
	fmt.Printf("Passed:   %s\n", successStyle.Render(fmt.Sprintf("%d", passed)))
	fmt.Printf("Failed:   %s\n", failStyle.Render(fmt.Sprintf("%d", failed)))
	fmt.Printf("Warnings: %s\n", warnStyle.Render(fmt.Sprintf("%d", warned)))
	fmt.Printf("Time:     %s\n", dimStyle.Render(elapsed.Round(time.Second).String()))
	fmt.Println()

	if failed == 0 {
		fmt.Println(successStyle.Render("✅ All solution validations passed"))
		os.Exit(0)
	} else {
		fmt.Println(failStyle.Render("❌ Some solution validations failed"))
		os.Exit(1)
	}
}
