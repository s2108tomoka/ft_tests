#!/bin/bash

# シンプルなシェル比較テスター（セグフォルト対策版）
# 使用方法: ./simple_test.sh

set -e

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MINISHELL=./minishell
TEST_FILE=minishell_testcase
# readline.suppファイルを作成
cat > readline.supp << 'EOF'
{
   exclude_readline_library
   Memcheck:Leak
   match-leak-kinds: all
   ...
   fun:rl_*
}

{
   exclude_readline_library2
   Memcheck:Leak
   match-leak-kinds: all
   ...
   fun:add_history
}

{
   exclude_readline_library3
   Memcheck:Leak
   match-leak-kinds: all
   ...
   fun:readline
}

{
   exclude_readline_library4
   Memcheck:Leak
   match-leak-kinds: all
   ...
   obj:*/libreadline.so*
}
EOF

# ファイル存在チェック
if [ ! -f "$MINISHELL" ] || [ ! -x "$MINISHELL" ]; then
    echo -e "${RED}エラー: '$MINISHELL' が見つからないか実行できません${NC}"
    exit 1
fi

if [ ! -f "$TEST_FILE" ]; then
    echo -e "${RED}エラー: '$TEST_FILE' が見つかりません${NC}"
    exit 1
fi

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}         minishell test${NC}"
echo -e "${BLUE}========================================${NC}"

TOTAL_TESTS=0
PASSED_TESTS=0

while IFS= read -r command || [ -n "$command" ]; do
    # 空行とコメント行をスキップ
    if [[ -z "$command" || "$command" =~ ^[[:space:]]*# ]]; then
        continue
    fi

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    echo -e "${YELLOW}テスト $TOTAL_TESTS:${NC} $command"

    # bashでの実行
    BASH_OUT="$TEMP_DIR/bash_out_$TOTAL_TESTS"
    echo "$command" | bash > "$BASH_OUT" 2>/dev/null || true

    # minishell用の入力ファイル作成
    INPUT_FILE="$TEMP_DIR/input_$TOTAL_TESTS"
    echo "$command" > "$INPUT_FILE"
    echo "exit" >> "$INPUT_FILE"

    # minishellでの実行（バックグラウンドで実行してタイムアウト制御）
    MINI_OUT="$TEMP_DIR/mini_out_$TOTAL_TESTS"

    # readline.suppファイルが存在する場合はvalgrindを使用
    if [ -f "readline.supp" ]; then
        # valgrindでメモリチェックしながら実行
        {
            timeout 10s valgrind --suppressions=readline.supp --leak-check=full --show-leak-kinds=all --track-origins=yes --quiet "$MINISHELL" < "$INPUT_FILE" 2>/dev/null || true
        } > "$MINI_OUT"
    else
        # 通常実行
        {
            timeout 5s "$MINISHELL" < "$INPUT_FILE" 2>/dev/null || true
        } > "$MINI_OUT"
    fi

    # プロンプトと空行を除去
    sed -i '/minishell.*\$/d' "$MINI_OUT"
    sed -i '/^[[:space:]]*$/d' "$MINI_OUT"

    # 結果比較
    if diff -q "$BASH_OUT" "$MINI_OUT" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "  ${RED}✗ FAIL${NC}"
        echo -e "  ${BLUE}期待値 (bash):${NC}"
        sed 's/^/    /' "$BASH_OUT"
        echo -e "  ${BLUE}実際の値 (minishell):${NC}"
        sed 's/^/    /' "$MINI_OUT"
    fi
    echo

done < "$TEST_FILE"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}         result${NC}"
echo -e "${BLUE}========================================${NC}"
echo "総テスト数: $TOTAL_TESTS"
echo -e "成功: ${GREEN}$PASSED_TESTS${NC}"
echo -e "失敗: ${RED}$((TOTAL_TESTS - PASSED_TESTS))${NC}"

if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo -e "${GREEN}すべてのテストが成功しました！${NC}"
else
    echo -e "${RED}$((TOTAL_TESTS - PASSED_TESTS)) 個のテストが失敗しました。${NC}"
fi
