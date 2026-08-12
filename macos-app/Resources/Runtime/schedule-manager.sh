#!/bin/bash

set -euo pipefail

LABEL="com.zhexin.volta-auto-update.scheduler"
SOURCE_RUNTIME_DIR=$(cd "$(dirname "$0")" && pwd)
UPDATER_SOURCE="${VOLTA_AUTO_UPDATE_SOURCE_UPDATER:-${SOURCE_RUNTIME_DIR}/update-volta-tools.sh}"
DATA_DIR="${VOLTA_AUTO_UPDATE_DATA_DIR:-${HOME}/Library/Application Support/Volta Auto Update}"
RUNTIME_DIR="${DATA_DIR}/Runtime"
LOG_DIR="${DATA_DIR}/Logs"
SCHEDULE_TIME_FILE="${DATA_DIR}/schedule-time"
LAUNCH_AGENTS_DIR="${VOLTA_AUTO_UPDATE_LAUNCH_AGENTS_DIR:-${HOME}/Library/LaunchAgents}"
PLIST_PATH="${LAUNCH_AGENTS_DIR}/${LABEL}.plist"
DOMAIN="gui/$(id -u)"
LAUNCHCTL="${VOLTA_AUTO_UPDATE_LAUNCHCTL:-/bin/launchctl}"
DEFAULT_SCHEDULE_TIME="09:00"

validate_schedule_time() {
    [[ "$1" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]
}

read_schedule_time() {
    local schedule_time="$DEFAULT_SCHEDULE_TIME"
    if [ -f "$SCHEDULE_TIME_FILE" ]; then
        schedule_time=$(/usr/bin/head -n 1 "$SCHEDULE_TIME_FILE" 2>/dev/null || true)
    fi

    if ! validate_schedule_time "$schedule_time"; then
        echo "[ERROR] 调度时间配置无效：${schedule_time}" >&2
        return 1
    fi
    printf '%s\n' "$schedule_time"
}

write_schedule_time() {
    local schedule_time=$1
    if ! validate_schedule_time "$schedule_time"; then
        echo "[ERROR] 调度时间必须使用 HH:MM 格式" >&2
        return 1
    fi

    /bin/mkdir -p "$DATA_DIR"
    printf '%s\n' "$schedule_time" > "${SCHEDULE_TIME_FILE}.tmp.$$"
    /bin/mv -f "${SCHEDULE_TIME_FILE}.tmp.$$" "$SCHEDULE_TIME_FILE"
}

ensure_schedule_time() {
    if [ ! -f "$SCHEDULE_TIME_FILE" ]; then
        write_schedule_time "$DEFAULT_SCHEDULE_TIME"
    else
        read_schedule_time >/dev/null
    fi
}

xml_escape() {
    printf '%s' "$1" | /usr/bin/sed \
        -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' \
        -e "s/'/\&apos;/g"
}

sed_replacement_escape() {
    printf '%s' "$1" | /usr/bin/sed -e 's/[&|]/\\&/g'
}

sync_runtime() {
    /bin/mkdir -p "$RUNTIME_DIR" "$LOG_DIR"
    ensure_schedule_time
    /usr/bin/install -m 755 "${SOURCE_RUNTIME_DIR}/scheduled-update.sh" "${RUNTIME_DIR}/scheduled-update.sh"
    /usr/bin/install -m 755 "$UPDATER_SOURCE" "${RUNTIME_DIR}/update-volta-tools.sh"
}

render_plist() {
    /bin/mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR"

    local runner_path
    local home_path
    local volta_home
    local stdout_log
    local stderr_log
    local temporary_plist
    local schedule_time
    local schedule_hour
    local schedule_minute

    runner_path=$(sed_replacement_escape "$(xml_escape "${RUNTIME_DIR}/scheduled-update.sh")")
    home_path=$(sed_replacement_escape "$(xml_escape "$HOME")")
    volta_home=$(sed_replacement_escape "$(xml_escape "${HOME}/.volta")")
    stdout_log=$(sed_replacement_escape "$(xml_escape "${LOG_DIR}/launchd.stdout.log")")
    stderr_log=$(sed_replacement_escape "$(xml_escape "${LOG_DIR}/launchd.stderr.log")")
    schedule_time=$(read_schedule_time)
    schedule_hour="${schedule_time%:*}"
    schedule_minute="${schedule_time#*:}"
    schedule_hour="${schedule_hour#0}"
    schedule_minute="${schedule_minute#0}"
    [ -n "$schedule_hour" ] || schedule_hour=0
    [ -n "$schedule_minute" ] || schedule_minute=0
    temporary_plist="${PLIST_PATH}.tmp.$$"

    /usr/bin/sed \
        -e "s|__RUNNER_PATH__|${runner_path}|g" \
        -e "s|__HOME_PATH__|${home_path}|g" \
        -e "s|__VOLTA_HOME__|${volta_home}|g" \
        -e "s|__STDOUT_LOG__|${stdout_log}|g" \
        -e "s|__STDERR_LOG__|${stderr_log}|g" \
        -e "s|__HOUR__|${schedule_hour}|g" \
        -e "s|__MINUTE__|${schedule_minute}|g" \
        "${SOURCE_RUNTIME_DIR}/launch-agent.plist.template" > "$temporary_plist"

    /usr/bin/plutil -lint "$temporary_plist" >/dev/null
    /usr/bin/install -m 600 "$temporary_plist" "$PLIST_PATH"
    /bin/unlink "$temporary_plist"
}

enable_schedule() {
    if [ -n "${1:-}" ]; then
        write_schedule_time "$1"
    fi
    sync_runtime
    render_plist
    "$LAUNCHCTL" bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
    "$LAUNCHCTL" enable "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
    "$LAUNCHCTL" bootstrap "$DOMAIN" "$PLIST_PATH"
    echo "enabled"
}

disable_schedule() {
    "$LAUNCHCTL" bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
    if [ -f "$PLIST_PATH" ]; then
        /bin/unlink "$PLIST_PATH"
    fi
    echo "disabled"
}

schedule_status() {
    local schedule_time
    schedule_time=$(read_schedule_time)
    if "$LAUNCHCTL" print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
        echo "enabled|${schedule_time}"
    else
        echo "disabled|${schedule_time}"
    fi
}

set_schedule_time() {
    local schedule_time=$1
    local was_enabled=0
    if "$LAUNCHCTL" print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
        was_enabled=1
    fi

    write_schedule_time "$schedule_time"
    if [ "$was_enabled" -eq 1 ]; then
        sync_runtime
        render_plist
        "$LAUNCHCTL" bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
        "$LAUNCHCTL" bootstrap "$DOMAIN" "$PLIST_PATH"
    fi
    echo "$schedule_time"
}

case "${1:-}" in
    enable)
        enable_schedule "${2:-}"
        ;;
    disable)
        disable_schedule
        ;;
    status)
        schedule_status
        ;;
    sync)
        sync_runtime
        echo "synced"
        ;;
    set-time)
        if [ -z "${2:-}" ]; then
            echo "[ERROR] 缺少调度时间" >&2
            exit 64
        fi
        set_schedule_time "$2"
        ;;
    *)
        echo "用法：$0 {enable [HH:MM]|disable|status|sync|set-time HH:MM}" >&2
        exit 64
        ;;
esac
