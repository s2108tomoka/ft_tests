#!/bin/bash

# テスト設定
TSET_DIR="tests_map"
TEST_FILES=(
    "no_collection.ber"
    "no_exit.ber"
    "no_square.ber"
    "empty.ber"
    "no_ber"
    "add_error_char.ber"
    "add_exit.ber"
    "add_start_posi.ber"
    "no_start_posi.ber"
    "no_enclosed.ber"
    "cannot_clear.ber"
    "cannot_clear2.ber"
    "no_sach_file.ber"
    "no_middleline.ber"
    "no_oneline.ber"
)

NAME="so_long"

LEAK_FLAG="valgrind --leak-check=full --show-leak-kinds=all"
LEAK_FLAG_Q="valgrind --leak-check=full --show-leak-kinds=all -q"

run_tests() {
    echo "== Running map tests =="

    for file in "${TEST_FILES[@]}"; do
        echo -e "\033[32m==> Running $file\033[0m"
        $LEAK_FLAG_Q ../$NAME $TSET_DIR/$file || true
    done
}

run_leak_tests() {
    echo "== Running leak tests =="

    for file in "${TEST_FILES[@]}"; do
        echo -e "\033[32m==> Running leak test for $file\033[0m"
        $LEAK_FLAG ../$NAME $TSET_DIR/$file || true
    done
}

case "${1:-test}" in
    "test")
        run_tests
        ;;
    "leak")
        run_leak_tests
        ;;
    *)
        echo "Usage: $0 [test|leak]"
        echo "  test: Run normal tests (default)"
        echo "  leak: Run tests with full valgrind output"
        exit 1
        ;;
esac
