#!/bin/bash

set -u

printf '%s\n' "${VOLTA_AUTO_UPDATE_TEST_DATE:-unknown}" >> "${MOCK_SCHEDULER_CALL_LOG}"
echo "模拟更新执行：${VOLTA_AUTO_UPDATE_TEST_DATE:-unknown}"
exit "${MOCK_SCHEDULER_EXIT_CODE:-0}"
