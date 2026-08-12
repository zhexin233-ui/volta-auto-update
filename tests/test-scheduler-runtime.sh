#!/bin/bash

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
RUNTIME_DIR="${PROJECT_DIR}/macos-app/Resources/Runtime"
MOCK_UPDATER="${PROJECT_DIR}/tests/fixtures/mock-scheduled-updater.sh"
MOCK_LAUNCHCTL="${PROJECT_DIR}/tests/fixtures/mock-launchctl.sh"
TEST_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/volta-scheduler-tests.XXXXXX")
CALL_LOG="${TEST_TEMP_DIR}/calls.log"
LAUNCHCTL_LOG="${TEST_TEMP_DIR}/launchctl.log"

cleanup() {
    rm -rf "$TEST_TEMP_DIR"
}
trap cleanup EXIT

fail() {
    echo "调度测试失败：$1" >&2
    exit 1
}

assert_count() {
    local expected=$1
    local actual=0
    if [ -f "$CALL_LOG" ]; then
        actual=$(wc -l < "$CALL_LOG" | tr -d ' ')
    fi
    [ "$actual" -eq "$expected" ] || fail "期望执行 ${expected} 次，实际 ${actual} 次"
}

reset_call_log() {
    : > "$CALL_LOG"
}

run_scheduled() {
    local data_dir=$1
    local date=$2
    local time=$3
    local mode=$4
    VOLTA_AUTO_UPDATE_DATA_DIR="$data_dir" \
        VOLTA_AUTO_UPDATE_SCRIPT="$MOCK_UPDATER" \
        VOLTA_AUTO_UPDATE_TEST_DATE="$date" \
        VOLTA_AUTO_UPDATE_TEST_TIME="$time" \
        MOCK_SCHEDULER_CALL_LOG="$CALL_LOG" \
        /bin/bash "${RUNTIME_DIR}/scheduled-update.sh" "$mode"
}

test_before_nine_waits_for_schedule() {
    reset_call_log
    local data_dir="${TEST_TEMP_DIR}/before-nine"
    run_scheduled "$data_dir" "2026-08-08" "0830" scheduled
    assert_count 0
    [ ! -f "${data_dir}/last-run-date" ] || fail "09:00 前不应占用当天执行额度"
}

test_daily_gate_and_next_day() {
    reset_call_log
    local data_dir="${TEST_TEMP_DIR}/daily-gate"
    run_scheduled "$data_dir" "2026-08-08" "0900" scheduled
    run_scheduled "$data_dir" "2026-08-08" "1200" scheduled
    assert_count 1
    grep -Fq '"state":"success"' "${data_dir}/status.json" || fail "成功状态未写入"

    run_scheduled "$data_dir" "2026-08-09" "0900" scheduled
    assert_count 2
}

test_manual_run_bypasses_daily_gate() {
    reset_call_log
    local data_dir="${TEST_TEMP_DIR}/manual"
    run_scheduled "$data_dir" "2026-08-08" "1000" scheduled
    run_scheduled "$data_dir" "2026-08-08" "1001" manual
    assert_count 2
}

test_failure_and_lock_status() {
    reset_call_log
    local failure_dir="${TEST_TEMP_DIR}/failure"
    set +e
    VOLTA_AUTO_UPDATE_DATA_DIR="$failure_dir" \
        VOLTA_AUTO_UPDATE_SCRIPT="$MOCK_UPDATER" \
        VOLTA_AUTO_UPDATE_TEST_DATE="2026-08-10" \
        VOLTA_AUTO_UPDATE_TEST_TIME="1000" \
        MOCK_SCHEDULER_CALL_LOG="$CALL_LOG" \
        MOCK_SCHEDULER_EXIT_CODE=7 \
        /bin/bash "${RUNTIME_DIR}/scheduled-update.sh" manual >/dev/null 2>&1
    local exit_code=$?
    set -e
    [ "$exit_code" -eq 7 ] || fail "底层退出码应原样返回"
    grep -Fq '"state":"failed"' "${failure_dir}/status.json" || fail "失败状态未写入"

    local lock_dir="${TEST_TEMP_DIR}/locked"
    mkdir -p "${lock_dir}/update.lock"
    printf '%s\n' "$$" > "${lock_dir}/update.lock/pid"
    set +e
    VOLTA_AUTO_UPDATE_DATA_DIR="$lock_dir" \
        VOLTA_AUTO_UPDATE_SCRIPT="$MOCK_UPDATER" \
        MOCK_SCHEDULER_CALL_LOG="$CALL_LOG" \
        /bin/bash "${RUNTIME_DIR}/scheduled-update.sh" manual >/dev/null 2>&1
    exit_code=$?
    set -e
    [ "$exit_code" -eq 75 ] || fail "并发手动任务应返回 75"
}

test_custom_schedule_time() {
    reset_call_log
    local data_dir="${TEST_TEMP_DIR}/custom-time"
    mkdir -p "$data_dir"
    printf '14:30\n' > "${data_dir}/schedule-time"

    run_scheduled "$data_dir" "2026-08-11" "1429" scheduled
    assert_count 0
    run_scheduled "$data_dir" "2026-08-11" "1430" scheduled
    assert_count 1
}

test_schedule_manager() {
    local data_dir="${TEST_TEMP_DIR}/Application Support/Manager"
    local agents_dir="${TEST_TEMP_DIR}/Launch Agents"
    : > "$LAUNCHCTL_LOG"

    VOLTA_AUTO_UPDATE_DATA_DIR="$data_dir" \
        VOLTA_AUTO_UPDATE_LAUNCH_AGENTS_DIR="$agents_dir" \
        VOLTA_AUTO_UPDATE_LAUNCHCTL="$MOCK_LAUNCHCTL" \
        VOLTA_AUTO_UPDATE_SOURCE_UPDATER="${PROJECT_DIR}/update-volta-tools.sh" \
        MOCK_LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        /bin/bash "${RUNTIME_DIR}/schedule-manager.sh" enable >/dev/null

    local plist="${agents_dir}/com.zhexin.volta-auto-update.scheduler.plist"
    [ -f "$plist" ] || fail "enable 未生成 LaunchAgent plist"
    /usr/bin/plutil -lint "$plist" >/dev/null || fail "LaunchAgent plist 无效"
    grep -Fq '<integer>9</integer>' "$plist" || fail "每日 09:00 未写入 plist"
    grep -Fq 'bootstrap' "$LAUNCHCTL_LOG" || fail "未调用 launchctl bootstrap"

    VOLTA_AUTO_UPDATE_DATA_DIR="$data_dir" \
        VOLTA_AUTO_UPDATE_LAUNCH_AGENTS_DIR="$agents_dir" \
        VOLTA_AUTO_UPDATE_LAUNCHCTL="$MOCK_LAUNCHCTL" \
        VOLTA_AUTO_UPDATE_SOURCE_UPDATER="${PROJECT_DIR}/update-volta-tools.sh" \
        MOCK_LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        /bin/bash "${RUNTIME_DIR}/schedule-manager.sh" set-time 14:30 >/dev/null
    grep -Fq '<integer>14</integer>' "$plist" || fail "自定义小时未写入 plist"
    grep -Fq '<integer>30</integer>' "$plist" || fail "自定义分钟未写入 plist"

    VOLTA_AUTO_UPDATE_DATA_DIR="$data_dir" \
        VOLTA_AUTO_UPDATE_LAUNCH_AGENTS_DIR="$agents_dir" \
        VOLTA_AUTO_UPDATE_LAUNCHCTL="$MOCK_LAUNCHCTL" \
        VOLTA_AUTO_UPDATE_SOURCE_UPDATER="${PROJECT_DIR}/update-volta-tools.sh" \
        MOCK_LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        /bin/bash "${RUNTIME_DIR}/schedule-manager.sh" disable >/dev/null
    [ ! -f "$plist" ] || fail "disable 后 plist 仍存在"
}

: > "$CALL_LOG"
test_before_nine_waits_for_schedule
test_daily_gate_and_next_day
test_manual_run_bypasses_daily_gate
test_failure_and_lock_status
test_custom_schedule_time
test_schedule_manager

echo "调度运行层测试全部通过。"
