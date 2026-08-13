#!/bin/bash

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT_PATH="${PROJECT_DIR}/update-volta-tools.sh"
FIXTURE_DIR="${PROJECT_DIR}/tests/fixtures"
TEST_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/volta-auto-update-tests.XXXXXX")
INSTALL_LOG="${TEST_TEMP_DIR}/install.log"
STDOUT_LOG="${TEST_TEMP_DIR}/stdout.log"
STDERR_LOG="${TEST_TEMP_DIR}/stderr.log"

cleanup() {
    rm -rf "$TEST_TEMP_DIR"
}
trap cleanup EXIT

fail() {
    echo "测试失败：$1" >&2
    exit 1
}

assert_contains() {
    local file=$1
    local expected=$2
    grep -Fq "$expected" "$file" || fail "${file} 不包含：${expected}"
}

assert_count() {
    local file=$1
    local expected=$2
    local pattern=$3
    local actual
    actual=$(grep -Fc "$pattern" "$file" || true)
    [ "$actual" -eq "$expected" ] || fail "${pattern} 期望出现 ${expected} 次，实际 ${actual} 次"
}

reset_mocks() {
    export MOCK_VOLTA_LIST_OUTPUT='package @openai/codex@1.0.0\npackage @anthropic-ai/claude-code@1.0.0\npackage opencode-ai@1.0.0\n'
    export MOCK_CURL_MODE=success
    export MOCK_CODEX_LATEST=1.0.0
    export MOCK_CLAUDE_LATEST=1.0.0
    export MOCK_OPENCODE_LATEST=1.0.0
    export MOCK_CUSTOM_LATEST=1.0.0
    export MOCK_VOLTA_FAIL_PACKAGE=''
    export MOCK_VOLTA_LIST_FAIL=0
    export MOCK_TOOLS_FILE="${TEST_TEMP_DIR}/missing-tools.tsv"
    : > "$INSTALL_LOG"
    : > "$STDOUT_LOG"
    : > "$STDERR_LOG"
}

run_script() {
    PATH="${FIXTURE_DIR}:/usr/bin:/bin" \
        MOCK_INSTALL_LOG="$INSTALL_LOG" \
        VOLTA_AUTO_UPDATE_TOOLS_FILE="$MOCK_TOOLS_FILE" \
        /bin/bash "$SCRIPT_PATH" > "$STDOUT_LOG" 2> "$STDERR_LOG"
}

test_all_latest() {
    reset_mocks
    run_script || fail "全部为最新版本时应退出 0"

    assert_contains "$STDOUT_LOG" "所有工具已是最新版本！"
    assert_contains "$STDOUT_LOG" "跳过：3 个工具"
    [ ! -s "$INSTALL_LOG" ] || fail "全部为最新版本时不应执行安装"
}

test_network_failure_is_soft() {
    reset_mocks
    export MOCK_CURL_MODE=network
    run_script || fail "网络失败属于非致命错误，应退出 0"

    assert_contains "$STDOUT_LOG" "没有可执行的更新。"
    assert_count "$STDERR_LOG" 3 "reason=网络请求失败"
    [ ! -s "$INSTALL_LOG" ] || fail "网络失败时不应执行安装"
}

test_parse_failure_is_soft() {
    reset_mocks
    export MOCK_CURL_MODE=parse
    run_script || fail "JSON 解析失败属于非致命错误，应退出 0"

    assert_count "$STDERR_LOG" 3 "reason=JSON 解析失败"
    [ ! -s "$INSTALL_LOG" ] || fail "JSON 解析失败时不应执行安装"
}

test_install_failure_does_not_stop_following_tools() {
    reset_mocks
    export MOCK_CODEX_LATEST=2.0.0
    export MOCK_CLAUDE_LATEST=2.0.0
    export MOCK_OPENCODE_LATEST=2.0.0
    export MOCK_VOLTA_FAIL_PACKAGE='@openai/codex@latest'
    run_script || fail "单个安装失败属于非致命错误，应退出 0"

    assert_contains "$STDOUT_LOG" "成功：2 个工具"
    assert_contains "$STDOUT_LOG" "失败：1 个工具"
    assert_contains "$STDOUT_LOG" "失败工具： Codex"
    assert_contains "$STDERR_LOG" "reason=模拟安装失败：@openai/codex@latest"
    assert_count "$INSTALL_LOG" 3 "@latest"
}

test_unknown_and_not_installed_are_distinct() {
    reset_mocks
    export MOCK_VOLTA_LIST_OUTPUT='package @openai/codex@1.0.0\npackage @anthropic-ai/claude-code\n'
    run_script || fail "版本未知或未安装属于非致命错误，应退出 0"

    assert_contains "$STDERR_LOG" "tool=@anthropic-ai/claude-code action=check reason=已安装版本解析失败"
    assert_contains "$STDERR_LOG" "tool=opencode-ai action=check reason=工具未安装"
    [ ! -s "$INSTALL_LOG" ] || fail "没有可更新项时不应执行安装"
}

test_volta_list_failure_is_soft() {
    reset_mocks
    export MOCK_VOLTA_LIST_FAIL=1
    run_script || fail "Volta 列表读取失败属于单项检查错误，应退出 0"

    assert_count "$STDERR_LOG" 3 "reason=已安装版本解析失败"
    [ ! -s "$INSTALL_LOG" ] || fail "Volta 列表读取失败时不应执行安装"
}

test_default_volta_home_is_discovered() {
    reset_mocks
    local isolated_home="${TEST_TEMP_DIR}/home"
    local path_without_volta="${TEST_TEMP_DIR}/path-without-volta"
    mkdir -p "${isolated_home}/.volta/bin" "$path_without_volta"
    cp "${FIXTURE_DIR}/volta" "${isolated_home}/.volta/bin/volta"
    cp "${FIXTURE_DIR}/curl" "${path_without_volta}/curl"
    cp "${FIXTURE_DIR}/pgrep" "${path_without_volta}/pgrep"
    chmod +x "${isolated_home}/.volta/bin/volta" "${path_without_volta}/curl" "${path_without_volta}/pgrep"

    HOME="$isolated_home" \
        VOLTA_HOME='' \
        PATH="${path_without_volta}:/usr/bin:/bin" \
        MOCK_INSTALL_LOG="$INSTALL_LOG" \
        VOLTA_AUTO_UPDATE_TOOLS_FILE="$MOCK_TOOLS_FILE" \
        /bin/bash "$SCRIPT_PATH" > "$STDOUT_LOG" 2> "$STDERR_LOG" \
        || fail "应能从默认的 ~/.volta/bin 找到 Volta"

    assert_contains "$STDOUT_LOG" "所有工具已是最新版本！"
}

test_homebrew_volta_is_discovered() {
    reset_mocks
    local isolated_home="${TEST_TEMP_DIR}/homebrew-home"
    local homebrew_prefix="${TEST_TEMP_DIR}/homebrew"
    local path_without_volta="${TEST_TEMP_DIR}/homebrew-path-without-volta"
    mkdir -p "$isolated_home" "${homebrew_prefix}/bin" "$path_without_volta"
    cp "${FIXTURE_DIR}/volta" "${homebrew_prefix}/bin/volta"
    cp "${FIXTURE_DIR}/curl" "${path_without_volta}/curl"
    cp "${FIXTURE_DIR}/pgrep" "${path_without_volta}/pgrep"
    chmod +x "${homebrew_prefix}/bin/volta" "${path_without_volta}/curl" "${path_without_volta}/pgrep"

    HOME="$isolated_home" \
        VOLTA_HOME="${isolated_home}/.volta" \
        HOMEBREW_PREFIX="$homebrew_prefix" \
        PATH="${path_without_volta}:/usr/bin:/bin" \
        MOCK_INSTALL_LOG="$INSTALL_LOG" \
        VOLTA_AUTO_UPDATE_TOOLS_FILE="$MOCK_TOOLS_FILE" \
        /bin/bash "$SCRIPT_PATH" > "$STDOUT_LOG" 2> "$STDERR_LOG" \
        || fail "应能从 Homebrew 的 bin 目录找到 Volta"

    assert_contains "$STDOUT_LOG" "所有工具已是最新版本！"
}

test_custom_tool_configuration() {
    reset_mocks
    MOCK_TOOLS_FILE="${TEST_TEMP_DIR}/custom-tools.tsv"
    printf 'custom-tool\t自定义工具\n' > "$MOCK_TOOLS_FILE"
    export MOCK_VOLTA_LIST_OUTPUT='package custom-tool@1.0.0\n'
    run_script || fail "自定义工具配置应正常执行"

    assert_contains "$STDOUT_LOG" "自定义工具"
    assert_contains "$STDOUT_LOG" "1 个工具"
    if grep -Fq "Codex" "$STDOUT_LOG"; then
        fail "存在自定义配置时不应回退默认工具"
    fi
}

test_empty_and_invalid_tool_configuration() {
    reset_mocks
    MOCK_TOOLS_FILE="${TEST_TEMP_DIR}/empty-tools.tsv"
    : > "$MOCK_TOOLS_FILE"
    run_script || fail "显式空工具配置应正常完成"
    assert_contains "$STDOUT_LOG" "0 个工具"

    MOCK_TOOLS_FILE="${TEST_TEMP_DIR}/invalid-tools.tsv"
    printf 'not a valid package\t错误工具\n' > "$MOCK_TOOLS_FILE"
    if run_script; then
        fail "非法工具配置应返回失败"
    fi
    assert_contains "$STDERR_LOG" "npm 包名不合法"
}

bash -n "$SCRIPT_PATH"
bash -n "${PROJECT_DIR}/update-volta-tools.command"

test_all_latest
test_network_failure_is_soft
test_parse_failure_is_soft
test_install_failure_does_not_stop_following_tools
test_unknown_and_not_installed_are_distinct
test_volta_list_failure_is_soft
test_default_volta_home_is_discovered
test_homebrew_volta_is_discovered
test_custom_tool_configuration
test_empty_and_invalid_tool_configuration

echo "全部测试通过。"
