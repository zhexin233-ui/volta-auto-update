#!/bin/bash

set -euo pipefail

# 工具列表定义（使用普通数组以兼容 Bash 3.2）
PACKAGES=("@openai/codex" "@anthropic-ai/claude-code" "@google/gemini-cli")
DISPLAY_NAMES=("Codex" "Claude Code" "Gemini CLI")

# 计数器初始化
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# 存储版本信息（使用普通数组）
CURRENT_VERSIONS=()
LATEST_VERSIONS=()
VERSION_STATUS=()

# 环境检查
check_environment() {
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
    local version

    version=$(volta list all 2>/dev/null | grep "^package ${package}@" | awk '{print $2}' | cut -d'@' -f3 || echo "")

    if [ -z "$version" ]; then
        echo "NOT_INSTALLED"
    else
        echo "$version"
    fi
}

# 检查最新版本
check_latest_version() {
    local package=$1
    local response
    local version

    response=$(curl -fsSL --connect-timeout 5 --max-time 10 --retry 2 --retry-delay 1 \
        "https://registry.npmjs.org/${package}/latest" 2>&1)

    if [ $? -ne 0 ]; then
        echo "NETWORK_ERROR"
        return
    fi

    version=$(echo "$response" | grep '"version"' | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "")

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

    echo "🔄 正在更新 ${display_name} 从 ${current} 到 ${latest}..."

    if volta install "${package}@latest" >/dev/null 2>&1; then
        echo "✓ ${display_name} 已更新到 ${latest}"
        ((SUCCESS_COUNT++))
        return 0
    else
        echo "[ERROR] tool=${package} action=update reason=volta install 失败" >&2
        ((FAIL_COUNT++))
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
        ((i++))
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
    echo "========================================"
}

# 主函数
main() {
    check_environment

    echo "🔍 Volta 工具自动更新器"
    echo "正在检查以下工具的版本："
    for display_name in "${DISPLAY_NAMES[@]}"; do
        echo "  - ${display_name}"
    done
    echo ""

    # 版本检查循环
    local need_update=0
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
            ((i++))
            continue
        fi

        local latest
        latest=$(check_latest_version "$package")
        LATEST_VERSIONS+=("$latest")

        if [ "$latest" = "NETWORK_ERROR" ]; then
            VERSION_STATUS+=("✗ 检查失败")
            echo "[ERROR] tool=${package} action=check reason=网络请求失败" >&2
            ((i++))
            continue
        fi

        if [ "$latest" = "PARSE_ERROR" ]; then
            VERSION_STATUS+=("✗ 检查失败")
            echo "[ERROR] tool=${package} action=check reason=JSON 解析失败" >&2
            ((i++))
            continue
        fi

        if [ "$current" != "$latest" ]; then
            VERSION_STATUS+=("⚠️ 需要更新")
            need_update=1
        else
            VERSION_STATUS+=("✓ 最新")
        fi
        ((i++))
    done

    show_version_table

    # 更新循环
    if [ $need_update -eq 0 ]; then
        echo "所有工具已是最新版本！"
        echo ""
        read -p "按任意键关闭..." -n1
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
            update_tool "$package" "$display_name" "$current" "$latest"
        else
            ((SKIP_COUNT++))
        fi
        ((i++))
    done

    show_summary
    echo ""
    read -p "按任意键关闭..." -n1
    exit 0
}

main
