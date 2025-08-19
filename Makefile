CC = gcc
CFLAGS = -Wall -Wextra -Werror -std=c99
TARGET = tester
SOURCE = tester.c

all: $(TARGET)

$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCE)

clean:
	rm -f $(TARGET)

test: $(TARGET)
	./$(TARGET) ./minishell test_cases.txt

help:
	@echo "Available targets:"
	@echo "  all     - Build the tester"
	@echo "  clean   - Remove built files"
	@echo "  test    - Run tests (requires ./minishell executable)"
	@echo "  help    - Show this help message"

.PHONY: all clean test help
