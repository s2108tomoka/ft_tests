#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counter for tests
TOTAL_TESTS=0
PASSED_TESTS=0
LEAK_TESTS=0
LEAK_PASSED=0

# Valgrind options (removed --error-exitcode since we want to check output content)
VALGRIND_OPTS="--leak-check=full --show-leak-kinds=all --track-origins=yes -q"

# Function to check for memory leaks with valgrind
check_memory_leaks() {
    local test_name="$1"
    shift
    local args="$@"

    LEAK_TESTS=$((LEAK_TESTS + 1))

    echo -e "${BLUE}  Checking memory leaks...${NC}"

    # Run with valgrind and capture output
    valgrind_output=$(valgrind $VALGRIND_OPTS ../push_swap $args 2>&1)

    # Check if there are actual memory leaks (not just program errors)
    if echo "$valgrind_output" | grep -E "(definitely lost|indirectly lost|possibly lost)" > /dev/null; then
        echo -e "${RED}  [LEAK]${NC} Memory leaks detected"
        # Show detailed leak information
        echo -e "${YELLOW}  Detailed leak report:${NC}"
        echo "$valgrind_output" | grep -E "(definitely lost|indirectly lost|possibly lost|Invalid|LEAK SUMMARY)"
    else
        echo -e "${GREEN}  [LEAK-FREE]${NC} No memory leaks detected"
        LEAK_PASSED=$((LEAK_PASSED + 1))
    fi
}

check_sorted(){
    local test_name="$1"
    shift
    local args="$@"

    # Run with valgrind and capture output
    checker_output=$(../push_swap $args | ../checker $args)

    echo "$checker_output"
    if [ "$checker_output" = "OK" ]; then
        echo -e  "${GREEN}  [SORTED]${NC} sorted"
    else
        echo -e "${RED}  [NOT SORTED]${NC} not sorted"
    fi
}

# Function to print test results
print_result() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}[PASS]${NC} $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}[FAIL]${NC} $test_name"
        echo -e "  Expected: $expected"
        echo -e "  Actual: $actual"
    fi
}
print_succes() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    echo -e "${GREEN}[PASS]${NC} $test_name"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "  Expected: $expected"
    echo -e "  Actual: $actual"
}

# Function to test push_swap and check if output is empty
test_sorted_input() {
    local test_name="$1"
    shift
    local args="$@"

    echo -e "${YELLOW}Testing:${NC} $test_name ($args)"

    # Run push_swap and capture output
    output=$(../push_swap $args 2>&1)
    exit_code=$?

    # Check if already sorted (should have no output)
    if [ -z "$output" ]; then
        print_result "$test_name" "empty" "empty"
    else
        print_result "$test_name" "empty" "not empty"
    fi

    # Check for memory leaks
    check_memory_leaks "$test_name" $args
    echo
}

# Function to test push_swap and verify sorting works
test_unsorted_input() {
    local test_name="$1"
    shift
    local args="$@"

    echo -e "${YELLOW}Testing:${NC} $test_name ($args)"

    # Run push_swap and capture output
    output=$(../push_swap $args 2>&1)
    exit_code=$?

    # Check if there's output (unsorted input should produce operations)
    if [ -n "$output" ]; then
        print_result "$test_name" "has output" "has output"

        # Optional: Test if the operations actually sort the numbers
        # This would require implementing the checker logic
        echo "  Operations: $(echo "$output" | wc -l) lines"
    else
        print_result "$test_name" "has output" "empty"
    fi

    # Check for memory leaks
    check_memory_leaks "$test_name" $args
    check_sorted "$test_name" $args
    echo
}

# Function to test error cases
test_error_case() {
    local test_name="$1"
    shift
    local args="$@"

    echo -e "${YELLOW}Testing:${NC} $test_name ($args)"

    # Run push_swap and capture both stdout and stderr
    output=$(../push_swap $args 2>&1)
    exit_code=$?

    # Remove trailing whitespace and newlines for comparison
    clean_output=$(echo "$output" | tr -d '\n\r' | sed 's/[[:space:]]*$//')

    # Special case for "No arguments" - should have no output
    if [ "$test_name" = "No arguments" ]; then
        if [ -z "$clean_output" ] && [ $exit_code -eq 0 ]; then
            print_result "$test_name" "no output" "no output"
        else
            print_result "$test_name" "no output" "unexpected output/error"
            echo -e "  Output was: '$output'"
            echo -e "  Exit code was: $exit_code"
        fi
    else
        # Check if error is properly handled (exactly "Error" or exit code != 0)
        if [ "$clean_output" = "Error" ] || [ $exit_code -ne 0 ]; then
            print_result "$test_name" "error" "error"
        else
            print_result "$test_name" "error" "no error"
            echo -e "  Output was: '$output'"
        fi
    fi

    # Check for memory leaks even in error cases
    check_memory_leaks "$test_name" $args
    echo
}

test_command_count() {
    local test_name="$1"
    local max_commands=$2
    shift 2
    local args="$@"

    echo -e "${YELLOW}Testing:${NC} $test_name ($args) - max $max_commands commands"

    # Run push_swap and capture output
    output=$(../push_swap $args 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        print_result "$test_name" "≤$max_commands commands" "error (exit code: $exit_code)"
        echo -e "  Output was: '$output'"
    else
        # Count the number of commands (lines)
        command_count=$(echo "$output" | wc -l)

        # If output is empty, wc -l returns 1, but we want 0
        if [ -z "$output" ]; then
            command_count=0
        fi

        if [ $command_count -le $max_commands ]; then
            print_succes "$test_name" "≤$max_commands commands" "$command_count commands"
        else
            print_result "$test_name" "≤$max_commands commands" "$command_count commands (TOO MANY)"
            echo -e "  Commands were:"
            echo "$output" | head -20  # Show first 20 commands
            if [ $command_count -gt 20 ]; then
                echo -e "  ... (and $((command_count - 20)) more)"
            fi
        fi
    fi

    # Check for memory leaks
    check_memory_leaks "$test_name" $args
    echo
}

echo "=== PUSH_SWAP TESTER ==="
echo

# Check if push_swap executable exists
if [ ! -f "../push_swap" ]; then
    echo -e "${RED}Error: ../push_swap not found${NC}"
    exit 1
fi

# Check if valgrind is installed
if ! command -v valgrind &> /dev/null; then
    echo -e "${RED}Error: valgrind is not installed${NC}"
    echo "Please install valgrind: sudo apt-get install valgrind"
    exit 1
fi

Test cases for already sorted inputs (should output nothing)
echo -e "${YELLOW}=== Testing Already Sorted Inputs ===${NC}"
test_sorted_input "Single number" "1"
test_sorted_input "Two sorted numbers" "1 2"
test_sorted_input "Three sorted numbers" "1 2 3"
test_sorted_input "Four sorted numbers" "1 2 3 4"
test_sorted_input "Five sorted numbers" "1 2 3 4 5"

echo

# Test cases for unsorted inputs (should output operations)
echo -e "${YELLOW}=== Testing Unsorted Inputs ===${NC}"
test_unsorted_input "Two unsorted numbers" "2 1"
test_unsorted_input "Three unsorted numbers" "3 2 1"
test_unsorted_input "Three unsorted numbers v2" "1 3 2"
test_unsorted_input "Three unsorted numbers v3" "2 1 3"
test_unsorted_input "Four unsorted numbers" "4 3 2 1"
test_unsorted_input "Five unsorted numbers" "5 4 3 2 1"

echo

# Test cases for error conditions
echo -e "${YELLOW}=== Testing Error Cases ===${NC}"
test_error_case "No arguments"
test_error_case "A empty argument" '""'
test_error_case "A space argument" '" "'
test_error_case "Duplicate numbers" "1 2 2 3"
test_error_case "Invalid number" "1 abc 3"
test_error_case "Number too large" "1 2147483648"
test_error_case "Number too small" "-2147483649"
test_error_case "Empty argument" "1 '' 3"

echo
echo "=== TEST SUMMARY ==="
echo -e "Functionality tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $((TOTAL_TESTS - PASSED_TESTS))${NC}"
echo
echo -e "Memory leak tests: $LEAK_TESTS"
echo -e "${GREEN}Leak-free: $LEAK_PASSED${NC}"
echo -e "${RED}Leaks found: $((LEAK_TESTS - LEAK_PASSED))${NC}"

# Test cases for command count limits
echo -e "${YELLOW}=== Testing Command Count Limits ===${NC}"
test_command_count "3 numbers (reverse order)" 3 "3 2 1"
test_command_count "3 numbers (random)" 3 "2 3 1"
test_command_count "3 numbers (another case)" 3 "1 3 2"
test_command_count "5 numbers (reverse order)" 12 "5 4 3 2 1"
test_command_count "5 numbers (random case 1)" 12 "3 5 1 4 2"
test_command_count "5 numbers (random case 2)" 12 "4 1 5 2 3"
test_command_count "5 numbers (random case 3)" 12 "2 5 3 1 4"

if [ $PASSED_TESTS -eq $TOTAL_TESTS ] && [ $LEAK_PASSED -eq $LEAK_TESTS ]; then
    echo
    echo -e "${GREEN}🎉 All tests passed and no memory leaks detected!${NC}"
    exit 0
else
    echo
    if [ $PASSED_TESTS -ne $TOTAL_TESTS ]; then
        echo -e "${RED}❌ Some functionality tests failed.${NC}"
    fi
    if [ $LEAK_PASSED -ne $LEAK_TESTS ]; then
        echo -e "${RED}💧 Memory leaks detected in some tests.${NC}"
    fi
    exit 1
fi
