#!/bin/bash

set -euo pipefail

# 默认工具列表（使用普通数组以兼容 Bash 3.2）
DEFAULT_PACKAGES=("@openai/codex" "@anthropic-ai/claude-code" "opencode-ai")
DEFAULT_DISPLAY_NAMES=("Codex" "Claude Code" "opencode")
PACKAGES=()
DISPLAY_NAMES=()
TOOLS_FILE="${VOLTA_AUTO_UPDATE_TOOLS_FILE:-${HOME:-}/Library/Application Support/Volta Auto Update/tools.tsv}"

# 计数器初始化
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILED_TOOLS=()

# 存储版本信息（使用普通数组）
CURRENT_VERSIONS=()
LATEST_VERSIONS=()
VERSION_STATUS=()

# 加载 App 与命令行共享的工具配置
load_tool_config() {
    if [ ! -e "$TOOLS_FILE" ]; then
        PACKAGES=("${DEFAULT_PACKAGES[@]}")
        DISPLAY_NAMES=("${DEFAULT_DISPLAY_NAMES[@]}")
        return
    fi

    if [ ! -r "$TOOLS_FILE" ]; then
        echo "[ERROR] 工具配置不可读：${TOOLS_FILE}" >&2
        exit 1
    fi

    local line_number=0
    local line
    local package
    local display_name
    local existing_package
    local tab=$'\t'

    while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number + 1))
        line="${line%$'\r'}"
        [ -z "$line" ] && continue

        if [[ "$line" != *"$tab"* ]]; then
            echo "[ERROR] 工具配置无效：第 ${line_number} 行缺少制表符分隔" >&2
            exit 1
        fi

        package="${line%%$tab*}"
        display_name="${line#*$tab}"
        if [[ "$display_name" == *"$tab"* ]] || [ -z "$display_name" ]; then
            echo "[ERROR] 工具配置无效：第 ${line_number} 行显示名为空或字段过多" >&2
            exit 1
        fi

        if [[ ! "$package" =~ ^(@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$ ]]; then
            echo "[ERROR] 工具配置无效：第 ${line_number} 行 npm 包名不合法" >&2
            exit 1
        fi

        if [ "${#PACKAGES[@]}" -gt 0 ]; then
            for existing_package in "${PACKAGES[@]}"; do
                if [ "$existing_package" = "$package" ]; then
                    echo "[ERROR] 工具配置无效：第 ${line_number} 行包名重复" >&2
                    exit 1
                fi
            done
        fi

        PACKAGES+=("$package")
        DISPLAY_NAMES+=("$display_name")
    done < "$TOOLS_FILE"
}

# 补充非交互环境中的 Volta 路径（例如 launchd）
initialize_volta_path() {
    if command -v volta >/dev/null 2>&1; then
        return
    fi

    local volta_candidate
    local volta_candidates=()

    if [ -n "${VOLTA_HOME:-}" ]; then
        volta_candidates+=("${VOLTA_HOME}/bin/volta")
    fi
    if [ -n "${HOME:-}" ]; then
        volta_candidates+=("${HOME}/.volta/bin/volta")
    fi
    if [ -n "${HOMEBREW_PREFIX:-}" ]; then
        volta_candidates+=("${HOMEBREW_PREFIX}/bin/volta")
    fi
    volta_candidates+=("/opt/homebrew/bin/volta" "/usr/local/bin/volta")

    for volta_candidate in "${volta_candidates[@]}"; do
        if [ -x "$volta_candidate" ]; then
            export PATH="${volta_candidate%/*}:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"
            return
        fi
    done
}

# 环境检查
check_environment() {
    initialize_volta_path

    if ! command -v volta >/dev/null 2>&1; then
        echo "[ERROR] Volta 未安装，请先安装 Volta" >&2
        exit 1
    fi

    local current_pid=$$
    if pgrep -f "update-volta-tools" | grep -v "^${current_pid}$" >/dev/null 2>&1; then
        echo "[ERROR] 检测到其他实例正在运行，请稍后再试" >&2
        exit 1
    fi
}

# 检查已安装版本
check_installed_version() {
    local package=$1
    local volta_output
    local entry
    local version

    if ! volta_output=$(volta list all 2>/dev/null); then
        echo "UNKNOWN"
        return 0
    fi

    entry=$(printf '%s\n' "$volta_output" | awk -v package="$package" '$1 == "package" && ($2 == package || index($2, package "@") == 1) { print $2; exit }' || true)

    if [ -z "$entry" ]; then
        echo "NOT_INSTALLED"
    else
        version="${entry##*@}"
        if [ "$entry" = "$package" ] || [ -z "$version" ]; then
            echo "UNKNOWN"
        else
            echo "$version"
        fi
    fi
}

# 检查最新版本
check_latest_version() {
    local package=$1
    local response
    local version

    if ! response=$(curl -fsSL --connect-timeout 5 --max-time 10 --retry 2 --retry-delay 1 \
        "https://registry.npmjs.org/${package}/latest" 2>&1); then
        echo "NETWORK_ERROR"
        return 0
    fi

    version=$(printf '%s\n' "$response" | grep '"version"' | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)

    if [ -z "$version" ]; then
        echo "PARSE_ERROR"
    else
        echo "$version"
    fi
}

# 更新工具
update_tool() {
    local package=$1
    local display_name=$2
    local current=$3
    local latest=$4
    local install_output

    echo "🔄 正在更新 ${display_name} 从 ${current} 到 ${latest}..."

    if install_output=$(volta install "${package}@latest" 2>&1); then
        echo "✓ ${display_name} 已更新到 ${latest}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    else
        install_output=$(printf '%s' "$install_output" | tr '\r\n\t' '   ')
        if [ -z "$install_output" ]; then
            install_output="volta install 失败"
        fi
        echo "[ERROR] tool=${package} action=update reason=${install_output}" >&2
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_TOOLS+=("$display_name")
        return 1
    fi
}

# 显示版本对比表格
show_version_table() {
    echo ""
    echo "========================================"
    printf "%-20s %-12s %-12s %-15s\n" "工具名" "当前版本" "最新版本" "状态"
    echo "========================================"

    local i=0
    for package in "${PACKAGES[@]}"; do
        local display_name="${DISPLAY_NAMES[$i]}"
        local current="${CURRENT_VERSIONS[$i]}"
        local latest="${LATEST_VERSIONS[$i]}"
        local status="${VERSION_STATUS[$i]}"

        printf "%-20s %-12s %-12s %-15s\n" "$display_name" "$current" "$latest" "$status"
        i=$((i + 1))
    done

    echo "========================================"
    echo ""
}

# 显示最终摘要
show_summary() {
    echo ""
    echo "========================================"
    echo "更新完成！"
    echo "成功：${SUCCESS_COUNT} 个工具"
    echo "失败：${FAIL_COUNT} 个工具"
    echo "跳过：${SKIP_COUNT} 个工具"
    if [ "$FAIL_COUNT" -gt 0 ]; then
        printf "失败工具："
        local failed_tool
        for failed_tool in "${FAILED_TOOLS[@]}"; do
            printf " %s" "$failed_tool"
        done
        echo ""
    fi
    echo "========================================"
}

# 主函数
main() {
    load_tool_config

    if [ "${#PACKAGES[@]}" -eq 0 ]; then
        echo "🔍 Volta 工具自动更新器"
        echo "没有配置需要更新的工具。"
        show_summary
        exit 0
    fi

    check_environment

    echo "🔍 Volta 工具自动更新器"
    echo "正在检查以下工具的版本："
    for display_name in "${DISPLAY_NAMES[@]}"; do
        echo "  - ${display_name}"
    done
    echo ""

    # 版本检查循环
    local need_update=0
    local has_check_errors=0
    local i=0
    for package in "${PACKAGES[@]}"; do
        local display_name="${DISPLAY_NAMES[$i]}"
        echo "🔍 正在检查 ${display_name}..."

        local current
        current=$(check_installed_version "$package")
        CURRENT_VERSIONS+=("$current")

        if [ "$current" = "NOT_INSTALLED" ]; then
            LATEST_VERSIONS+=("N/A")
            VERSION_STATUS+=("✗ 未安装")
            echo "[ERROR] tool=${package} action=check reason=工具未安装" >&2
            has_check_errors=1
            i=$((i + 1))
            continue
        fi

        if [ "$current" = "UNKNOWN" ]; then
            LATEST_VERSIONS+=("N/A")
            VERSION_STATUS+=("✗ 检查失败")
            echo "[ERROR] tool=${package} action=check reason=已安装版本解析失败" >&2
            has_check_errors=1
            i=$((i + 1))
            continue
        fi

        local latest
        latest=$(check_latest_version "$package")
        LATEST_VERSIONS+=("$latest")

        if [ "$latest" = "NETWORK_ERROR" ]; then
            VERSION_STATUS+=("✗ 检查失败")
            echo "[ERROR] tool=${package} action=check reason=网络请求失败" >&2
            has_check_errors=1
            i=$((i + 1))
            continue
        fi

        if [ "$latest" = "PARSE_ERROR" ]; then
            VERSION_STATUS+=("✗ 检查失败")
            echo "[ERROR] tool=${package} action=check reason=JSON 解析失败" >&2
            has_check_errors=1
            i=$((i + 1))
            continue
        fi

        if [ "$current" != "$latest" ]; then
            VERSION_STATUS+=("⚠️ 需要更新")
            need_update=1
        else
            VERSION_STATUS+=("✓ 最新")
        fi
        i=$((i + 1))
    done

    show_version_table

    # 更新循环
    if [ "$need_update" -eq 0 ]; then
        if [ "$has_check_errors" -eq 0 ]; then
            echo "所有工具已是最新版本！"
        else
            echo "没有可执行的更新。"
        fi
        SKIP_COUNT=${#PACKAGES[@]}
        show_summary
        exit 0
    fi

    echo "开始更新过期的工具..."
    echo ""

    i=0
    for package in "${PACKAGES[@]}"; do
        local display_name="${DISPLAY_NAMES[$i]}"
        local status="${VERSION_STATUS[$i]}"

        if [ "$status" = "⚠️ 需要更新" ]; then
            local current="${CURRENT_VERSIONS[$i]}"
            local latest="${LATEST_VERSIONS[$i]}"
            if ! update_tool "$package" "$display_name" "$current" "$latest"; then
                : # 单个工具失败不应阻止后续更新
            fi
        else
            SKIP_COUNT=$((SKIP_COUNT + 1))
        fi
        i=$((i + 1))
    done

    show_summary
    exit 0
}

main
