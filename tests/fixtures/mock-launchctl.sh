#!/bin/bash

set -u

printf '%s\n' "$*" >> "${MOCK_LAUNCHCTL_LOG}"
exit 0
