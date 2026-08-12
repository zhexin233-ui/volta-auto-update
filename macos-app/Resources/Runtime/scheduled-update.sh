#!/bin/bash

set -uo pipefail

MODE="${1:-scheduled}"
if [ "$MODE" != "scheduled" ] && [ "$MODE" != "manual" ]; then
    echo "[ERROR] 未知运行模式：${MODE}" >&2
    exit 64
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DATA_DIR="${VOLTA_AUTO_UPDATE_DATA_DIR:-${HOME}/Library/Application Support/Volta Auto Update}"
LOG_DIR="${DATA_DIR}/Logs"
STATE_FILE="${DATA_DIR}/status.json"
LAST_RUN_DATE_FILE="${DATA_DIR}/last-run-date"
SCHEDULE_TIME_FILE="${DATA_DIR}/schedule-time"
TOOLS_FILE="${VOLTA_AUTO_UPDATE_TOOLS_FILE:-${DATA_DIR}/tools.tsv}"
LOCK_DIR="${DATA_DIR}/update.lock"
LOCK_PID_FILE="${LOCK_DIR}/pid"
LOG_FILE="${LOG_DIR}/update.log"
UPDATER_SCRIPT="${VOLTA_AUTO_UPDATE_SCRIPT:-${SCRIPT_DIR}/update-volta-tools.sh}"
TODAY="${VOLTA_AUTO_UPDATE_TEST_DATE:-$(/bin/date '+%Y-%m-%d')}"
CURRENT_TIME="${VOLTA_AUTO_UPDATE_TEST_TIME:-$(/bin/date '+%H%M')}"
SCHEDULE_TIME="09:00"
if [ -f "$SCHEDULE_TIME_FILE" ]; then
    SCHEDULE_TIME=$(/usr/bin/head -n 1 "$SCHEDULE_TIME_FILE" 2>/dev/null || true)
fi
if [[ ! "$SCHEDULE_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "[ERROR] 调度时间配置无效：${SCHEDULE_TIME}" >&2
    exit 1
fi
SCHEDULE_HHMM="${SCHEDULE_TIME/:/}"

/bin/mkdir -p "$DATA_DIR" "$LOG_DIR"

json_escape() {
    printf '%s' "$1" | /usr/bin/sed \
        -e 's/\\/\\\\/g' \
        -e 's/"/\\"/g'
}

write_status() {
    local state=$1
    local started_at=$2
    local finished_at=$3
    local exit_code=$4
    local reason=$5
    local temporary_status="${STATE_FILE}.tmp.$$"

    printf '{"schemaVersion":1,"state":"%s","mode":"%s","startedAt":"%s","finishedAt":"%s","exitCode":%s,"reason":"%s","pid":%s,"logPath":"%s"}\n' \
        "$(json_escape "$state")" \
        "$(json_escape "$MODE")" \
        "$(json_escape "$started_at")" \
        "$(json_escape "$finished_at")" \
        "$exit_code" \
        "$(json_escape "$reason")" \
        "$$" \
        "$(json_escape "$LOG_FILE")" > "$temporary_status"
    /bin/mv -f "$temporary_status" "$STATE_FILE"
}

release_lock() {
    if [ -f "$LOCK_PID_FILE" ]; then
        /bin/unlink "$LOCK_PID_FILE" >/dev/null 2>&1 || true
    fi
    if [ -d "$LOCK_DIR" ]; then
        /bin/rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
    fi
}

acquire_lock() {
    if /bin/mkdir "$LOCK_DIR" >/dev/null 2>&1; then
        printf '%s\n' "$$" > "$LOCK_PID_FILE"
        return 0
    fi

    local existing_pid=""
    if [ -f "$LOCK_PID_FILE" ]; then
        existing_pid=$(/bin/cat "$LOCK_PID_FILE" 2>/dev/null || true)
    fi

    if [ -n "$existing_pid" ] && ! /bin/kill -0 "$existing_pid" >/dev/null 2>&1; then
        /bin/unlink "$LOCK_PID_FILE" >/dev/null 2>&1 || true
        /bin/rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
        if /bin/mkdir "$LOCK_DIR" >/dev/null 2>&1; then
            printf '%s\n' "$$" > "$LOCK_PID_FILE"
            return 0
        fi
    fi

    return 1
}

rotate_log_if_needed() {
    if [ ! -f "$LOG_FILE" ]; then
        return
    fi

    local size
    size=$(/usr/bin/stat -f '%z' "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt 2097152 ]; then
        /usr/bin/tail -n 2000 "$LOG_FILE" > "${LOG_FILE}.tmp.$$"
        /bin/mv -f "${LOG_FILE}.tmp.$$" "$LOG_FILE"
    fi
}

if [ "$MODE" = "scheduled" ] && [ "$CURRENT_TIME" -lt "$SCHEDULE_HHMM" ]; then
    exit 0
fi

if ! acquire_lock; then
    if [ "$MODE" = "manual" ]; then
        echo "[ERROR] 已有更新任务正在运行" >&2
        exit 75
    fi
    exit 0
fi
trap release_lock EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

last_run_date=""
if [ -f "$LAST_RUN_DATE_FILE" ]; then
    last_run_date=$(/bin/cat "$LAST_RUN_DATE_FILE" 2>/dev/null || true)
fi

if [ "$MODE" = "scheduled" ] && [ "$last_run_date" = "$TODAY" ]; then
    exit 0
fi

printf '%s\n' "$TODAY" > "${LAST_RUN_DATE_FILE}.tmp.$$"
/bin/mv -f "${LAST_RUN_DATE_FILE}.tmp.$$" "$LAST_RUN_DATE_FILE"

rotate_log_if_needed
started_at=$(/bin/date '+%Y-%m-%dT%H:%M:%S%z')
write_status "running" "$started_at" "" "null" ""

{
    echo ""
    echo "===== ${started_at} mode=${MODE} ====="
} | /usr/bin/tee -a "$LOG_FILE"

set +e
VOLTA_AUTO_UPDATE_TOOLS_FILE="$TOOLS_FILE" /bin/bash "$UPDATER_SCRIPT" 2>&1 | /usr/bin/tee -a "$LOG_FILE"
update_exit_code=${PIPESTATUS[0]}
set -e

finished_at=$(/bin/date '+%Y-%m-%dT%H:%M:%S%z')
if [ "$update_exit_code" -eq 0 ]; then
    write_status "success" "$started_at" "$finished_at" "$update_exit_code" ""
else
    write_status "failed" "$started_at" "$finished_at" "$update_exit_code" "更新脚本退出码 ${update_exit_code}"
fi

exit "$update_exit_code"
