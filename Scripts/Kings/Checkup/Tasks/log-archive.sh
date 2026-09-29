#!/bin/bash
# Moves each past month's daily logs into logs/YYYY-MM.zip. Every pending month is handled,
# so a machine that stayed off for a while catches up in a single run.

. "$(dirname "${BASH_SOURCE[0]}")/../../../Core/log.sh"

cd "$KINGS_LOG_DIR" 2> /dev/null || exit 0
current="$(date +%Y-%m)"

for month in $(ls | sed -n 's/^\([0-9]\{4\}-[0-9]\{2\}\)-[0-9]\{2\}\.log$/\1/p' | sort -u); do
  [[ "$month" < "$current" ]] || continue
  zip -q -m "$month.zip" "$month"-*.log || exit 1
  log "Archived $month logs into $month.zip"
done
