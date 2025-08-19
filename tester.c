#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <errno.h>

#define MAX_CMD_LEN 1024
#define MAX_OUTPUT_LEN 4096

typedef struct {
    char *stdout_content;
    char *stderr_content;
    int exit_code;
} TestResult;

// 色付きの出力用のマクロ
#define RED     "\x1b[31m"
#define GREEN   "\x1b[32m"
#define YELLOW  "\x1b[33m"
#define BLUE    "\x1b[34m"
#define MAGENTA "\x1b[35m"
#define CYAN    "\x1b[36m"
#define RESET   "\x1b[0m"

// strdupの代替実装（環境によっては利用できない場合があるため）
char *my_strdup(const char *s) {
    if (s == NULL) return NULL;
    size_t len = strlen(s) + 1;
    char *dup = malloc(len);
    if (dup == NULL) return NULL;
    memcpy(dup, s, len);
    return dup;
}

void free_test_result(TestResult *result) {
    if (result->stdout_content) {
        free(result->stdout_content);
        result->stdout_content = NULL;
    }
    if (result->stderr_content) {
        free(result->stderr_content);
        result->stderr_content = NULL;
    }
}

char *read_file_content(const char *filename) {
    FILE *file = fopen(filename, "r");
    if (!file) {
        return NULL;
    }

    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    fseek(file, 0, SEEK_SET);

    char *content = malloc(size + 1);
    if (!content) {
        fclose(file);
        return NULL;
    }

    fread(content, 1, size, file);
    content[size] = '\0';
    fclose(file);

    return content;
}

TestResult execute_command(const char *command, const char *shell_path) {
    TestResult result = {0};
    char stdout_file[] = "/tmp/minishell_test_stdout_XXXXXX";
    char stderr_file[] = "/tmp/minishell_test_stderr_XXXXXX";

    int stdout_fd = mkstemp(stdout_file);
    int stderr_fd = mkstemp(stderr_file);

    if (stdout_fd == -1 || stderr_fd == -1) {
        perror("mkstemp failed");
        result.exit_code = -1;
        return result;
    }

    pid_t pid = fork();
    if (pid == 0) {
        // 子プロセス
        dup2(stdout_fd, STDOUT_FILENO);
        dup2(stderr_fd, STDERR_FILENO);
        close(stdout_fd);
        close(stderr_fd);

        execl(shell_path, shell_path, "-c", command, NULL);
        exit(127); // execl failed
    } else if (pid > 0) {
        // 親プロセス
        int status;
        waitpid(pid, &status, 0);

        if (WIFEXITED(status)) {
            result.exit_code = WEXITSTATUS(status);
        } else {
            result.exit_code = -1;
        }

        close(stdout_fd);
        close(stderr_fd);

        result.stdout_content = read_file_content(stdout_file);
        result.stderr_content = read_file_content(stderr_file);

        unlink(stdout_file);
        unlink(stderr_file);
    } else {
        perror("fork failed");
        result.exit_code = -1;
    }

    return result;
}

void print_diff(const char *expected, const char *actual, const char *type) {
    if (expected == NULL) expected = "";
    if (actual == NULL) actual = "";

    printf("    %s%s Difference:%s\n", YELLOW, type, RESET);
    printf("      %sExpected:%s\n", GREEN, RESET);

    if (strlen(expected) == 0) {
        printf("        %s(empty)%s\n", CYAN, RESET);
    } else {
        char *expected_copy = my_strdup(expected);
        char *line = strtok(expected_copy, "\n");
        while (line) {
            printf("        %s> %s%s\n", GREEN, line, RESET);
            line = strtok(NULL, "\n");
        }
        free(expected_copy);
    }

    printf("      %sActual:%s\n", RED, RESET);
    if (strlen(actual) == 0) {
        printf("        %s(empty)%s\n", CYAN, RESET);
    } else {
        char *actual_copy = my_strdup(actual);
        char *line = strtok(actual_copy, "\n");
        while (line) {
            printf("        %s> %s%s\n", RED, line, RESET);
            line = strtok(NULL, "\n");
        }
        free(actual_copy);
    }
}

int run_test(const char *command, const char *minishell_path) {
    printf("%s\n", command);

    // bashで期待する結果を取得
    TestResult bash_result = execute_command(command, "/bin/bash");

    // minishellで実際の結果を取得
    TestResult minishell_result = execute_command(command, minishell_path);

    int test_passed = 1;

    // STDOUT比較
    if (bash_result.stdout_content == NULL || minishell_result.stdout_content == NULL) {
        if (bash_result.stdout_content != minishell_result.stdout_content) {
            test_passed = 0;
            print_diff(bash_result.stdout_content, minishell_result.stdout_content, "STDOUT");
        }
    } else if (strcmp(bash_result.stdout_content, minishell_result.stdout_content) != 0) {
        test_passed = 0;
        print_diff(bash_result.stdout_content, minishell_result.stdout_content, "STDOUT");
    }

    // STDERR比較
    if (bash_result.stderr_content == NULL || minishell_result.stderr_content == NULL) {
        if (bash_result.stderr_content != minishell_result.stderr_content) {
            test_passed = 0;
            print_diff(bash_result.stderr_content, minishell_result.stderr_content, "STDERR");
        }
    } else if (strcmp(bash_result.stderr_content, minishell_result.stderr_content) != 0) {
        test_passed = 0;
        print_diff(bash_result.stderr_content, minishell_result.stderr_content, "STDERR");
    }

    // Exit code比較
    if (bash_result.exit_code != minishell_result.exit_code) {
        test_passed = 0;
        printf("    %sExit Code Difference:%s\n", YELLOW, RESET);
        printf("      %sExpected:%s %d\n", GREEN, RESET, bash_result.exit_code);
        printf("      %sActual:%s %d\n", RED, RESET, minishell_result.exit_code);
    }

    if (test_passed) {
        printf("    %s✓ PASSED%s\n", GREEN, RESET);
    } else {
        printf("    %s✗ FAILED%s\n", RED, RESET);
    }

    printf("\n");

    free_test_result(&bash_result);
    free_test_result(&minishell_result);

    return test_passed;
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <minishell_path> <test_file>\n", argv[0]);
        printf("Example: %s ./minishell test_cases.txt\n", argv[0]);
        return 1;
    }

    char *minishell_path = argv[1];
    char *test_file = argv[2];

    // minishellの存在確認
    if (access(minishell_path, X_OK) != 0) {
        printf("%sError: minishell '%s' is not executable or doesn't exist%s\n",
               RED, minishell_path, RESET);
        return 1;
    }

    // テストファイルを読み込み
    FILE *file = fopen(test_file, "r");
    if (!file) {
        printf("%sError: Cannot open test file '%s'%s\n", RED, test_file, RESET);
        return 1;
    }

    printf("%s=== Minishell Tester ===%s\n", MAGENTA, RESET);
    printf("Minishell: %s\n", minishell_path);
    printf("Test file: %s\n\n", test_file);

    char command[MAX_CMD_LEN];
    int total_tests = 0;
    int passed_tests = 0;
    int test_number = 1;

    while (fgets(command, sizeof(command), file)) {
        // 改行文字を削除
        command[strcspn(command, "\n")] = '\0';

        // 空行やコメント行をスキップ
        if (strlen(command) == 0 || command[0] == '#') {
            continue;
        }

        printf("%sTest %d: %s", CYAN, test_number++,RESET);

        if (run_test(command, minishell_path)) {
            passed_tests++;
        }
        total_tests++;
    }

    fclose(file);

    printf("%s=== Test Summary ===%s\n", MAGENTA, RESET);
    printf("Total tests: %d\n", total_tests);
    printf("Passed: %s%d%s\n", GREEN, passed_tests, RESET);
    printf("Failed: %s%d%s\n", RED, total_tests - passed_tests, RESET);

    if (passed_tests == total_tests) {
        printf("%sAll tests passed! 🎉%s\n", GREEN, RESET);
        return 0;
    } else {
        printf("%sSome tests failed. 😞%s\n", RED, RESET);
        return 1;
    }
}
