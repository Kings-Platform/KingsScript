#!/bin/bash
# Core checkup tasks. Sourced by checkup.sh: `checkup_task <id> <daily|weekly|monthly> <script>`.

checkup_task log-archive monthly "$CHECKUP_DIR/Tasks/log-archive.sh"
checkup_task ai-update daily "$CHECKUP_DIR/Tasks/ai-update.sh"
